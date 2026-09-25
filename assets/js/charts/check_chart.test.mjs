import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createCanvas, loadImage} from '@napi-rs/canvas';
import {
  checkChartConfig, createCheckChart, CHECK_CHART_HEIGHT,
  SNAPSHOT_WIDTH, SNAPSHOT_HEIGHT, SNAPSHOT_PADDING, SNAPSHOT_PIXEL_RATIO,
} from './check_chart.mjs';

const data = {
  labels: ['10:00', '10:01', '10:02'], values: [100, 110, 200],
  success: [1, 1, 0], average: 136.67,
  alert_type: 'anomaly', alert_threshold: {upper: 120, lower: 80},
};

test('site and snapshot share all datasets, scales, legend, and point colors', () => {
  const site = checkChartConfig(data);
  const snapshot = checkChartConfig(data, {snapshot: true});
  assert.equal(JSON.stringify(site.data), JSON.stringify(snapshot.data));
  assert.deepEqual(site.options.scales.x.title, snapshot.options.scales.x.title);
  assert.deepEqual(site.options.scales.y, snapshot.options.scales.y);
  assert.deepEqual(site.options.plugins, snapshot.options.plugins);
  assert.deepEqual(site.data.datasets.map(d => d.label), ['Value', 'Average', 'Upper Threshold', 'Lower Threshold']);
  assert.equal(site.data.datasets[1].data[0], 136.67); // Average of displayed values, not anomaly mean.
  for (let dataIndex = 0; dataIndex < data.values.length; dataIndex++) {
    assert.equal(site.data.datasets[0].pointBackgroundColor({dataIndex}), snapshot.data.datasets[0].pointBackgroundColor({dataIndex}));
  }
  assert.equal(site.data.datasets[0].pointBackgroundColor({dataIndex: 2}), '#fbbe23');
  assert.equal(snapshot.options.animation, false);
});

test('minute history uses times on the axis while retaining full dates in tooltips', () => {
  const labels = ['2026-09-25 12:01', '2026-09-25 12:02', '2026-09-25 12:03'];
  const canvas = createCanvas(SNAPSHOT_WIDTH, SNAPSHOT_HEIGHT);
  const chart = createCheckChart(canvas, {...data, labels}, {snapshot: true});
  try {
    assert.deepEqual(chart.scales.x.ticks.map(tick => tick.label), ['12:01', '12:02', '12:03']);
    assert.equal(chart.scales.x.options.title.text, '2026-09-25');
    assert.deepEqual(chart.data.labels, labels);
  } finally {
    chart.destroy();
  }
});

test('axis labels give date context at midnight and for longer histories', () => {
  const midnight = checkChartConfig({...data, labels: [
    '2026-09-24 23:59', '2026-09-25 00:00', '2026-09-25 00:01',
  ]});
  const axis = midnight.options.scales.x;
  assert.equal(axis.title.text, '2026-09-24 – 2026-09-25');
  assert.equal(axis.ticks.callback(0), '23:59');
  assert.equal(axis.ticks.callback(1), '00:00');

  const hourly = checkChartConfig({...data, labels: [
    '2026-09-24 12', '2026-09-25 12', '2026-09-26 12',
  ]});
  assert.equal(hourly.options.scales.x.ticks.callback(0), '09/24 12:00');
  assert.equal(hourly.options.scales.x.ticks.callback(2), '09/26 12:00');

  const daily = checkChartConfig({...data, labels: [
    '2025-12-31', '2026-01-01', '2026-01-02',
  ]});
  assert.equal(daily.options.scales.x.title.text, '2025-12-31 – 2026-01-02');
  assert.deepEqual([0, 1, 2].map(index => daily.options.scales.x.ticks.callback(index)),
    ['12/31', '01/01', '01/02']);
});

test('diff charts and sparse histories do not gain synthetic thresholds or values', () => {
  const config = checkChartConfig({...data, alert_type: 'diff', values: [0, null, 200]});
  assert.deepEqual(config.data.datasets.map(d => d.label), ['Value', 'Average']);
  assert.deepEqual(config.data.datasets[0].data, [0, null, 200]);
  assert.equal(config.data.datasets[0].tension, 0.4);
});

test('renders the shared chart at a taller snapshot height', async () => {
  assert.equal(CHECK_CHART_HEIGHT, 256);
  assert.equal(SNAPSHOT_HEIGHT, 280);
  const canvas = createCanvas(SNAPSHOT_WIDTH, SNAPSHOT_HEIGHT);
  const chart = createCheckChart(canvas, data, {snapshot: true});
  try {
    const png = await canvas.encode('png');
    assert.equal(png.readUInt32BE(16), SNAPSHOT_WIDTH * SNAPSHOT_PIXEL_RATIO);
    assert.equal(png.readUInt32BE(20), SNAPSHOT_HEIGHT * SNAPSHOT_PIXEL_RATIO);
    const points = chart.getDatasetMeta(0).data;
    assert(points[0].x < points[1].x && points[1].x < points[2].x);
    assert(points[2].y < points[0].y);
    assert.equal(points[2].options.backgroundColor, '#fbbe23');
    assert.deepEqual([...canvas.getContext('2d').getImageData(0, 0, 1, 1).data], [255, 255, 255, 255]);
  } finally {
    chart.destroy();
  }
});

test('the exported Slack image has a 5px white border on every side', async () => {
  const renderer = fileURLToPath(new URL('./render_check_chart.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [renderer], {
    input: `${JSON.stringify(data)}\n`,
    maxBuffer: 4_000_000,
  });
  assert.equal(result.status, 0, result.stderr.toString());

  const inset = SNAPSHOT_PADDING * SNAPSHOT_PIXEL_RATIO;
  const width = (SNAPSHOT_WIDTH + SNAPSHOT_PADDING * 2) * SNAPSHOT_PIXEL_RATIO;
  const height = (SNAPSHOT_HEIGHT + SNAPSHOT_PADDING * 2) * SNAPSHOT_PIXEL_RATIO;
  assert.equal(result.stdout.readUInt32BE(16), width);
  assert.equal(result.stdout.readUInt32BE(20), height);

  const image = await loadImage(result.stdout);
  const canvas = createCanvas(width, height);
  const context = canvas.getContext('2d');
  context.drawImage(image, 0, 0);
  const pixels = context.getImageData(0, 0, width, height).data;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (x >= inset && x < width - inset && y >= inset && y < height - inset) continue;
      const offset = (y * width + x) * 4;
      if (pixels[offset] !== 255 || pixels[offset + 1] !== 255 ||
          pixels[offset + 2] !== 255 || pixels[offset + 3] !== 255) {
        assert.fail(`border pixel at (${x}, ${y}) is not opaque white`);
      }
    }
  }
});
