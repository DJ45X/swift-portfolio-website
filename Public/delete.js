// Admin-only delete confirmation. Each dashboard row has its own real
// <form action=".../delete">; this script intercepts the submit to show a
// custom confirmation modal first. If the script fails to load, the forms still
// work (they just delete without the modal) — the action lives in the HTML, so
// a submit can never be misrouted.
(function () {
    "use strict";

    var modal = document.getElementById("delete-modal");
    var confirmBtn = document.getElementById("delete-modal-confirm");
    var nameEl = document.getElementById("delete-modal-name");
    if (!modal || !confirmBtn) {
        return;
    }

    // The form awaiting confirmation.
    var pendingForm = null;

    function openModal(form) {
        pendingForm = form;
        if (nameEl) {
            var row = form.closest(".dash-list__item");
            var titleEl = row ? row.querySelector(".dash-list__title") : null;
            nameEl.textContent = titleEl ? titleEl.textContent.trim() : "this entry";
        }
        modal.hidden = false;
        document.body.classList.add("modal-open");
        var cancel = modal.querySelector("[data-close]");
        if (cancel && typeof cancel.focus === "function") {
            cancel.focus();
        }
    }

    function closeModal() {
        pendingForm = null;
        modal.hidden = true;
        document.body.classList.remove("modal-open");
    }

    document.querySelectorAll("[data-delete-form]").forEach(function (form) {
        form.addEventListener("submit", function (event) {
            // Intercept the native submit and confirm first.
            event.preventDefault();
            openModal(form);
        });
    });

    confirmBtn.addEventListener("click", function () {
        if (pendingForm) {
            // .submit() bypasses the submit event listener, so it posts directly.
            pendingForm.submit();
        }
    });

    modal.querySelectorAll("[data-close]").forEach(function (el) {
        el.addEventListener("click", closeModal);
    });

    document.addEventListener("keydown", function (event) {
        if (event.key === "Escape" && !modal.hidden) {
            closeModal();
        }
    });
})();
