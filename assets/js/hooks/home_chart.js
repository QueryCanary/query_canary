import {
    Chart,
    LineController,
    LineElement,
    BarController,
    BarElement,
    PointElement,
    LinearScale,
    CategoryScale,
    Tooltip,
    Legend,
  } from 'chart.js';
  
  Chart.register(
    LineController,
    LineElement,
    BarController,
    BarElement,
    PointElement,
    LinearScale,
    CategoryScale,
    Tooltip,
    Legend
  );

const HomeChart = {
    mounted() {
        this.renderChart();
    },

    renderChart() {
        if (this.chart) {
            this.chart.destroy();
        }

        const ctx = this.el.getContext('2d');
        let good = "#00d390";
        let warning = "#fcb700";
        let data = [124, 130, 98, 102, 180, 90, 45];
        new Chart(ctx, {
            type: 'line',
            data: {
            labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
            datasets: [
                {
                    label: 'User Registrations',
                    data: data,
                    borderColor: 'rgb(59, 130, 246)',
                    backgroundColor: 'rgba(59, 130, 246, 0.2)',
                    fill: false,
                    tension: 0.4,
                },
                {
                    label: "% Change from Avg",
                    data: [-9, -3, -26, -22, 33, -29, -60],
                    type: "bar",
                    backgroundColor: [good, good, good, good, good, good, warning],
                    yAxisID: 'y1',
                }
            ]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        beginAtZero: true
                    },

                    y1: {
                        type: 'linear',
                        position: 'right',
                        min: -100,
                        max: 100,
                        grid: { drawOnChartArea: false },
                        title: { display: true, text: 'Moving Average' },
                    }
                }
            }
        });
    },

    updated() {
        setTimeout(() => {
            this.renderChart();
        }, 100);
    },

    destroyed() {
        if (this.chart) {
            this.chart.destroy();
            this.chart = null;
        }
    },

    reconnected() {
        setTimeout(() => {
            this.renderChart();
        }, 100);
    }
};

export default HomeChart;