const CheckChart = {
    mounted() {
      this.renderChart();
    },
    
    renderChart() {
      // Clean up previous chart instance to prevent memory leaks
      if (this.chart) {
        this.chart.destroy();
      }
      
      const labels = JSON.parse(this.el.dataset.labels);
      const values = JSON.parse(this.el.dataset.values);
      const success = JSON.parse(this.el.dataset.success);
      const average = JSON.parse(this.el.dataset.average);
      const alertThreshold = JSON.parse(this.el.dataset.alertThreshold);
      const alertType = this.el.dataset.alertType;
      
      // Set explicit size constraints to prevent growth issues
      const parent = this.el.parentElement;
      this.el.style.width = '100%';
      this.el.style.height = '256px'; // Fixed height to prevent growth
      this.el.style.maxHeight = '400px'; // Maximum allowed height
      
      let datasets = [
        {
          label: "Value",
          data: values,
          borderColor: "#5c6ac4",
          backgroundColor: "rgba(92,106,196,0.1)",
          tension: 0.4,
          yAxisID: 'y',
          pointRadius: 4,
          pointHoverRadius: 6,
          pointBackgroundColor: (context) => {
            
            // Highlight the problematic points
            if (success[context.dataIndex] === 0) {
              return '#fbbe23';
            }
            if (alertType === 'diff' && context.dataIndex === values.length - 1) {
              return "#f87272";
            } else if (alertType === 'anomaly' && context.dataIndex === values.length - 1) {
              return "#fbbd23";
            }
            return "#5c6ac4";
          },
        },
        // {
        //   label: "Success",
        //   data: success,
        //   type: "bar",
        //   backgroundColor: (context) => {
        //     return success[context.dataIndex] === 1 ? "#36d399" : "#f87272";
        //   },
        //   yAxisID: 'y1',
        //   barPercentage: 0.2,
        // }
      ];
      
      // Add average line if available
      if (average !== null) {
        datasets.push({
          label: "Average",
          data: Array(labels.length).fill(average),
          borderColor: "#6c757d",
          borderWidth: 2,
          borderDash: [5, 5],
          fill: false,
          pointRadius: 0,
          yAxisID: 'y',
        });
      }
      
      // Add threshold lines for anomaly detection
      
      if (alertType === 'anomaly' && alertThreshold && alertThreshold.upper !== null && alertThreshold.lower !== null) {
        datasets.push({
          label: "Upper Threshold",
          data: Array(labels.length).fill(alertThreshold.upper),
          borderColor: "rgba(251, 189, 35, 0.7)",
          borderWidth: 2,
          borderDash: [5, 5],
          fill: false,
          pointRadius: 0,
          yAxisID: 'y',
        });
        
        datasets.push({
          label: "Lower Threshold",
          data: Array(labels.length).fill(alertThreshold.lower),
          borderColor: "rgba(251, 189, 35, 0.7)",
          borderWidth: 2,
          borderDash: [5, 5],
          fill: {
            target: '+1',
            above: 'rgba(251, 189, 35, 0.05)',
            below: 'rgba(251, 189, 35, 0.05)'
          },
          pointRadius: 0,
          yAxisID: 'y',
        });
      }
      
      // Use requestAnimationFrame to ensure DOM is ready
      requestAnimationFrame(() => {
        const ctx = this.el.getContext("2d");
        
        this.chart = new Chart(ctx, {
          type: "line",
          data: {
            labels: labels,
            datasets: datasets,
          },
          options: {
            responsive: true,
            maintainAspectRatio: false, // This can cause issues if not properly constrained
            animation: {
              duration: 500
            },
            resizeDelay: 200, // Add delay to prevent resize loops
            plugins: {
              tooltip: {
                mode: 'index',
                intersect: false,
                callbacks: {
                  footer: function(tooltipItems) {
                    const successItem = tooltipItems.find(item => item.dataset.label === 'Success');
                    if (successItem) {
                      return successItem.raw === 1 ? 'Status: Success' : 'Status: Failure';
                    }
                    return '';
                  }
                }
              },
              legend: {
                position: 'top',
                labels: {
                  boxWidth: 12,
                  usePointStyle: true,
                  filter: (legendItem) => {
                    // Hide threshold lines from legend if not relevant
                    if (alertType !== 'anomaly' && 
                        (legendItem.text === 'Upper Threshold' || 
                         legendItem.text === 'Lower Threshold')) {
                      return false;
                    }
                    return true;
                  }
                }
              }
            },
            scales: {
              x: {
                title: {
                  display: false,
                }
              },
              y: {
                type: 'linear',
                position: 'left',
                title: { display: true, text: 'Value' },
                beginAtZero: true
              },
              // y1: {
              //   type: 'linear',
              //   position: 'right',
              //   min: 0,
              //   max: 1,
              //   grid: { drawOnChartArea: false },
              //   title: { display: true, text: 'Status' },
              //   ticks: {
              //     callback: (val) => (val === 1 ? '✓' : '×'),
              //     stepSize: 1
              //   }
              // }
            },
          },
        });
      });
    },
    
    updated() {
      // Use setTimeout to create a separate event loop task,
      // preventing immediate re-renders that can cause a loop
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
      // Ensure the chart is properly redrawn on reconnect
      setTimeout(() => {
        this.renderChart();
      }, 100);
    }
  };
  
  export default CheckChart;