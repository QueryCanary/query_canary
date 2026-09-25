import {createCheckChart, CHECK_CHART_HEIGHT} from '../charts/check_chart.mjs';

export default {
  mounted() {
    this.renderChart();
  },

  renderChart() {
    cancelAnimationFrame(this.frame);
    this.frame = requestAnimationFrame(() => {
      this.chart?.destroy();
      this.el.style.width = '100%';
      this.el.style.height = `${CHECK_CHART_HEIGHT}px`;
      this.el.style.maxHeight = '400px';
      this.chart = createCheckChart(this.el, JSON.parse(this.el.dataset.chart));
    });
  },

  updated() {
    this.renderChart();
  },

  reconnected() {
    this.renderChart();
  },

  destroyed() {
    cancelAnimationFrame(this.frame);
    this.chart?.destroy();
    this.chart = null;
  },
};
