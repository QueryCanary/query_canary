const ACTIVE_DROP_CLASSES = ["ring-1", "ring-primary", "bg-primary/5"]

const clearDropTarget = (hook) => {
  if (hook.currentDropTarget) {
    hook.currentDropTarget.classList.remove(...ACTIVE_DROP_CLASSES)
    hook.currentDropTarget = null
  }
}

const setDropTarget = (hook, element) => {
  if (hook.currentDropTarget === element) return

  clearDropTarget(hook)

  if (element) {
    element.classList.add(...ACTIVE_DROP_CLASSES)
    hook.currentDropTarget = element
  }
}

const ReportMetricDrag = {
  mounted() {
    this.draggedMetricId = null
    this.currentDropTarget = null
    this.currentDragRow = null

    this.onDragStart = (event) => {
      const handle = event.target.closest("[data-draggable-metric-id][data-metric-drag-handle]")

      if (!handle) {
        event.preventDefault()
        return
      }

      const row = handle.closest("[data-metric-row-id]")

      this.draggedMetricId = handle.dataset.draggableMetricId
      this.currentDragRow = row
      row && row.classList.add("opacity-40")

      if (event.dataTransfer) {
        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("text/plain", this.draggedMetricId)
      }
    }

    this.onDragOver = (event) => {
      const dropTarget = event.target.closest("[data-metric-drop-group-id]")

      if (!this.draggedMetricId) return

      if (!dropTarget) {
        clearDropTarget(this)
        return
      }

      event.preventDefault()
      event.dataTransfer && (event.dataTransfer.dropEffect = "move")
      setDropTarget(this, dropTarget)
    }

    this.onDragLeave = (event) => {
      if (!this.currentDropTarget) return

      const related = event.relatedTarget

      if (related && this.currentDropTarget.contains(related)) return

      if (event.target === this.currentDropTarget) {
        clearDropTarget(this)
      }
    }

    this.onDrop = (event) => {
      const dropTarget = event.target.closest("[data-metric-drop-group-id]")

      if (!this.draggedMetricId || !dropTarget) return

      event.preventDefault()

      this.pushEvent("move_metric_to_group", {
        metric_group_id: this.draggedMetricId,
        target_group_id: dropTarget.dataset.metricDropGroupId,
        before_group_metric_id: dropTarget.dataset.metricDropBeforeId || ""
      })

      clearDropTarget(this)
      this.draggedMetricId = null
    }

    this.onDragEnd = () => {
      this.currentDragRow && this.currentDragRow.classList.remove("opacity-40")

      clearDropTarget(this)
      this.draggedMetricId = null
      this.currentDragRow = null
    }

    this.el.addEventListener("dragstart", this.onDragStart)
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("dragleave", this.onDragLeave)
    this.el.addEventListener("drop", this.onDrop)
    this.el.addEventListener("dragend", this.onDragEnd)
  },

  destroyed() {
    this.el.removeEventListener("dragstart", this.onDragStart)
    this.el.removeEventListener("dragover", this.onDragOver)
    this.el.removeEventListener("dragleave", this.onDragLeave)
    this.el.removeEventListener("drop", this.onDrop)
    this.el.removeEventListener("dragend", this.onDragEnd)
  }
}

export default ReportMetricDrag
