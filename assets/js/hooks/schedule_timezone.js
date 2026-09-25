export default {
  mounted() {
    if (this.el.dataset.autoTimezone !== "true") return;

    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const select = this.el.querySelector("[data-timezone-select]");

    if (timezone && select && [...select.options].some(option => option.value === timezone)) {
      this.pushEvent("detect_timezone", {timezone});
    }
  }
};
