// Theme toggle: flips between dark (default) and light, persisting the choice
// in localStorage. The initial theme is applied inline in <head> to avoid a
// flash of the wrong theme before this script runs.
(function () {
    "use strict";

    var toggle = document.getElementById("theme-toggle");
    if (!toggle) {
        return;
    }

    toggle.addEventListener("click", function () {
        var root = document.documentElement;
        var current = root.getAttribute("data-theme") === "light" ? "light" : "dark";
        var next = current === "dark" ? "light" : "dark";

        root.setAttribute("data-theme", next);
        localStorage.setItem("theme", next);
    });
})();
