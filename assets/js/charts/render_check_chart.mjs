import {createCanvas, GlobalFonts} from '@napi-rs/canvas';
import {existsSync} from 'node:fs';
import {createInterface} from 'node:readline';
import {
  createCheckChart, SNAPSHOT_WIDTH, SNAPSHOT_HEIGHT, SNAPSHOT_PADDING, SNAPSHOT_PIXEL_RATIO,
} from './check_chart.mjs';

// Liberation Sans is metrically compatible with Chart.js's Arial fallback on Linux.
const linuxFont = '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf';
if (existsSync(linuxFont)) GlobalFonts.registerFromPath(linuxFont, 'Arial');

// One bounded request per process. Input stays off the command line and disk.
const input = createInterface({input: process.stdin});
const deadline = setTimeout(() => process.exit(1), 9_000);
deadline.unref();
input.once('line', async line => {
  input.close();
  process.stdin.pause();
  let chart;
  try {
    const data = JSON.parse(line);
    if (!Array.isArray(data.labels) || data.labels.length > 48 ||
        !Array.isArray(data.values) || data.values.length !== data.labels.length) {
      throw new Error('Invalid chart data');
    }
    const canvas = createCanvas(SNAPSHOT_WIDTH, SNAPSHOT_HEIGHT);
    chart = createCheckChart(canvas, data, {snapshot: true});

    // Compose the high-resolution chart inside an exact 5px white border.
    const inset = SNAPSHOT_PADDING * SNAPSHOT_PIXEL_RATIO;
    const image = createCanvas(canvas.width + inset * 2, canvas.height + inset * 2);
    const context = image.getContext('2d');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, image.width, image.height);
    context.drawImage(canvas, inset, inset);

    const png = await image.encode('png');
    process.stdout.write(png, () => process.exit(0));
  } catch {
    // Do not print check data or native error objects into logs.
    process.exit(1);
  } finally {
    chart?.destroy();
  }
});
