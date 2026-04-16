let duration = 0;
let startTime = 0;
let running = false;

const circle = document.getElementById("progress-bar");
const percentText = document.getElementById("percent");

function GetParentResourceName() {
    try {
        const scripts = document.getElementsByTagName("script");
        for (let i = 0; i < scripts.length; i++) {
            const src = scripts[i].src;
            if (src && src.includes("nui://")) {
                const match = src.match(/nui:\/\/([^/]+)\//);
                if (match) return match[1];
            }
        }
    } catch (e) {}
    return "SP_DrugSellingV2";
}

window.addEventListener("message", function (event) {
    const data = event.data;
    if (data.action === "start") {
        document.getElementById("title").innerText = data.title || "Crafting";
        document.getElementById("desc").innerText = data.desc || "";
        duration = data.time || 5000;
        startTime = Date.now();
        running = true;
        const wrapper = document.getElementById("progress-wrapper");
        wrapper.classList.remove("hidden");
        wrapper.style.display = "block";
        wrapper.style.visibility = "visible";
        wrapper.style.opacity = "1";
        updateProgress();
    }
    if (data.action === "stop") stopProgress();

    if (data.action === "craftingOpen") {
        craftingOpenUI(data.medications, data.craftingType, data.label);
    }
    if (data.action === "craftingClose") craftingCloseUI();
    if (data.action === "showLoading") craftingShowLoading(data.text, data.duration);
    if (data.action === "updateProgress") craftingUpdateProgress(data.progress, data.text);
    if (data.action === "hideLoading") craftingHideLoading();
});

function updateProgress() {
    if (!running) return;

    const elapsed = Date.now() - startTime;
    const percent = Math.min((elapsed / duration) * 100, 100);

    const offset = 377 - (377 * percent) / 100;
    circle.style.strokeDashoffset = offset;
    percentText.innerText = Math.floor(percent) + "%";

    if (percent >= 100) {
        fetch(`https://${GetParentResourceName()}/finished`, { method: "POST" });
        stopProgress();
        return;
    }

    requestAnimationFrame(updateProgress);
}

function stopProgress() {
    running = false;
    const wrapper = document.getElementById("progress-wrapper");
    wrapper.classList.add("hidden");
    wrapper.style.display = "none";
    wrapper.style.visibility = "hidden";
    wrapper.style.opacity = "0";
}

var currentMedications = [];
var currentCraftingType = "";
var selectedCraftItem = null;

function craftingOpenUI(medications, craftingType, label) {
    currentMedications = medications || [];
    currentCraftingType = craftingType || "";
    document.getElementById("crafting-header-title").textContent = label || "Crafting";
    document.getElementById("crafting-app").classList.remove("hidden");
    var grid = document.getElementById("medicationsGrid");
    grid.innerHTML = "";
    currentMedications.forEach(function (med, index) {
        var card = document.createElement("div");
        card.className = "medication-card";
        card.onclick = function () { openCraftModal(index); };
        var outputText = (med.additems || []).map(function (i) { return i.amount + "x"; }).join(", ");
        var durationSec = Math.round((med.duration || 5000) / 1000);
        var requiredText = (med.requireditems && med.requireditems.length) ? med.requireditems.map(function (r) { return r.name; }).join(", ") : "None";
        card.innerHTML = "<div class=\"medication-card-header\"><div class=\"pill-icon\"><svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><path d=\"M6 8a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v8a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8z\"/><line x1=\"12\" y1=\"4\" x2=\"12\" y2=\"20\"/></svg></div><div class=\"medication-title\"><h3>" + (med.title || "Item") + "</h3><p>" + (med.description || "") + "</p></div></div><div class=\"medication-details\"><div class=\"detail-row\"><span class=\"label\">Time</span><span class=\"duration-badge\">" + durationSec + "s</span></div><div class=\"detail-row\"><span class=\"label\">Output</span><span class=\"value\">" + outputText + "</span></div><div class=\"detail-row\"><span class=\"label\">Materials</span><span class=\"required-badge\">" + requiredText + "</span></div></div>";
        grid.appendChild(card);
    });
}

function craftingCloseUI() {
    document.getElementById("crafting-app").classList.add("hidden");
    document.getElementById("crafting-modal-overlay").classList.add("hidden");
    craftingHideLoading();
    fetch("https://" + GetParentResourceName() + "/craftingCloseUI", { method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8" }, body: JSON.stringify({}) });
}

function openCraftModal(index) {
    var med = currentMedications[index];
    if (!med) return;
    selectedCraftItem = { index: med.index !== undefined ? med.index : index, luaIndex: med.luaIndex !== undefined ? med.luaIndex : index + 1, title: med.title, description: med.description, duration: med.duration || 5000, progressbar: med.progressbar || med.title, requireditems: med.requireditems || [], additems: med.additems || [] };
    document.getElementById("modalTitle").textContent = med.title || "Item";
    document.getElementById("modalDescription").textContent = med.description || "-";
    document.getElementById("modalDuration").textContent = Math.round((med.duration || 5000) / 1000) + " seconds";
    document.getElementById("modalOutput").textContent = (med.additems || []).map(function (i) { return i.amount + "x"; }).join(", ");
    var reqEl = document.getElementById("modalRequired");
    reqEl.innerHTML = "";
    if (med.requireditems && med.requireditems.length) {
        med.requireditems.forEach(function (r) {
            var div = document.createElement("div");
            div.className = "required-item";
            div.innerHTML = "<span>📦</span><span>" + r.amount + "x " + r.name + "</span>";
            reqEl.appendChild(div);
        });
    } else {
        reqEl.innerHTML = "<div class=\"required-item\"><span>📦</span><span>None</span></div>";
    }
    document.getElementById("crafting-modal-overlay").classList.remove("hidden");
}

function closeCraftModal() {
    document.getElementById("crafting-modal-overlay").classList.add("hidden");
    selectedCraftItem = null;
}

function beginCrafting() {
    if (!selectedCraftItem || !currentCraftingType) { closeCraftModal(); return; }
    var itemToSend = { index: selectedCraftItem.index, luaIndex: selectedCraftItem.luaIndex, title: selectedCraftItem.title || "", description: selectedCraftItem.description || "", duration: selectedCraftItem.duration || 5000, progressbar: selectedCraftItem.progressbar || selectedCraftItem.title || "", requireditems: selectedCraftItem.requireditems || [], additems: selectedCraftItem.additems || [] };
    closeCraftModal();
    fetch("https://" + GetParentResourceName() + "/craftItem", { method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8" }, body: JSON.stringify({ craftingType: currentCraftingType, item: itemToSend }) }).then(function (r) { return r.json(); }).then(function (resp) { if (!resp.success) craftingHideLoading(); }).catch(function () { craftingHideLoading(); });
}

function craftingShowLoading(text, duration) {
    document.getElementById("crafting-loading-text").textContent = text || "Crafting...";
    document.getElementById("crafting-loading").classList.remove("hidden");
    document.getElementById("crafting-progress-bar").style.width = "0%";
}

function craftingUpdateProgress(progress, text) {
    if (text) document.getElementById("crafting-loading-text").textContent = text;
    document.getElementById("crafting-progress-bar").style.width = (progress || 0) + "%";
}

function craftingHideLoading() {
    document.getElementById("crafting-loading").classList.add("hidden");
    document.getElementById("crafting-progress-bar").style.width = "0%";
}

document.getElementById("crafting-close-btn").addEventListener("click", craftingCloseUI);
document.getElementById("crafting-modal-overlay").addEventListener("click", function (e) { if (e.target.id === "crafting-modal-overlay") closeCraftModal(); });
document.getElementById("modalCloseBtn").addEventListener("click", closeCraftModal);
document.getElementById("modalCancelBtn").addEventListener("click", closeCraftModal);
document.getElementById("modalCraftBtn").addEventListener("click", beginCrafting);

document.addEventListener("keydown", function (e) { if (e.key === "Escape") { closeCraftModal(); craftingCloseUI(); } });
