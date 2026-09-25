import {
  Chart, LineController, LineElement, PointElement, LinearScale,
  CategoryScale, Tooltip, Legend,
} from 'chart.js';

Chart.register(LineController, LineElement, PointElement, LinearScale, CategoryScale, Tooltip, Legend);

export const CHECK_CHART_HEIGHT = 256;
export const SNAPSHOT_WIDTH = 960;
export const SNAPSHOT_HEIGHT = 280;
export const SNAPSHOT_PADDING = 5;
export const SNAPSHOT_PIXEL_RATIO = 2;

function timeAxis(labels) {
  const timestamps = labels.map(label => {
    const parts = /^(\d{4})-(\d{2})-(\d{2})(?: (\d{2})(?::(\d{2})(?::(\d{2}))?)?)?$/.exec(label);
    if (!parts) return null;

    const [, year, month, day, hour, minute, second] = parts;
    const time = hour === undefined ? null :
      `${hour}:${minute ?? '00'}${second === undefined ? '' : `:${second}`}`;
    return {
      date: `${year}-${month}-${day}`,
      shortDate: `${month}/${day}`,
      time,
      epoch: Date.UTC(+year, +month - 1, +day, +(hour ?? 0), +(minute ?? 0), +(second ?? 0)),
    };
  });

  if (timestamps.length === 0 || timestamps.some(timestamp => timestamp === null)) {
    return {title: {display: false}};
  }

  const first = timestamps[0];
  const last = timestamps[timestamps.length - 1];
  const showTimeOnly = timestamps.every(timestamp => timestamp.time !== null) &&
    last.epoch - first.epoch < 24 * 60 * 60 * 1000;
  const tickLabels = timestamps.map(timestamp => {
    if (showTimeOnly) return timestamp.time;
    return timestamp.time === null ? timestamp.shortDate : `${timestamp.shortDate} ${timestamp.time}`;
  });

  return {
    title: {display: true, text: first.date === last.date ? first.date : `${first.date} – ${last.date}`},
    ticks: {callback(value) { return tickLabels[value] ?? this.getLabelForValue(value); }},
  };
}

// Both the LiveView canvas and the notification renderer use this definition.
export function checkChartConfig(data, {snapshot = false} = {}) {
  const {labels, values, success, average, alert_threshold: threshold, alert_type: alertType} = data;
  const datasets = [{
    label: 'Value',
    data: values,
    borderColor: '#5c6ac4',
    backgroundColor: 'rgba(92,106,196,0.1)',
    tension: 0.4,
    yAxisID: 'y',
    pointRadius: 4,
    pointHoverRadius: 6,
    pointBackgroundColor: context => {
      if (success[context.dataIndex] === 0) return '#fbbe23';
      if (context.dataIndex === values.length - 1) {
        if (alertType === 'diff') return '#f87272';
        if (alertType === 'anomaly') return '#fbbd23';
      }
      return '#5c6ac4';
    },
  }];

  const referenceLine = (label, value, color) => ({
    label,
    data: Array(labels.length).fill(value),
    borderColor: color,
    borderWidth: 2,
    borderDash: [5, 5],
    fill: false,
    pointRadius: 0,
    yAxisID: 'y',
  });

  if (average !== null) datasets.push(referenceLine('Average', average, '#6c757d'));
  if (alertType === 'anomaly' && threshold?.upper != null && threshold?.lower != null) {
    datasets.push(referenceLine('Upper Threshold', threshold.upper, 'rgba(251, 189, 35, 0.7)'));
    datasets.push(referenceLine('Lower Threshold', threshold.lower, 'rgba(251, 189, 35, 0.7)'));
  }

  return {
    type: 'line',
    data: {labels, datasets},
    options: {
      responsive: !snapshot,
      maintainAspectRatio: false,
      animation: snapshot ? false : {duration: 500},
      resizeDelay: 200,
      ...(snapshot ? {devicePixelRatio: SNAPSHOT_PIXEL_RATIO, events: []} : {}),
      plugins: {
        tooltip: {mode: 'index', intersect: false},
        legend: {position: 'top', labels: {boxWidth: 12, usePointStyle: true}},
      },
      scales: {
        x: timeAxis(labels),
        y: {type: 'linear', position: 'left', title: {display: true, text: 'Value'}},
      },
    },
    // The site canvas inherits its card's background. Images need an opaque matte.
    plugins: snapshot ? [{
      id: 'snapshotBackground',
      beforeDraw(chart) {
        const ctx = chart.ctx;
        ctx.save();
        ctx.globalCompositeOperation = 'destination-over';
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, chart.width, chart.height);
        ctx.restore();
      },
    }] : [],
  };
}

export function createCheckChart(canvas, data, options) {
  return new Chart(canvas, checkChartConfig(data, options));
}
