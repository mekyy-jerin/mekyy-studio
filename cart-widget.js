/* MekyyStudio floating cart + payment widget */
(() => {
  const cssClass = "mekyy-cart";
  function getCart() {
    try { return JSON.parse(localStorage.getItem("studio-cart") || "[]"); }
    catch { return []; }
  }
  function saveCart(v) {
    localStorage.setItem("studio-cart", JSON.stringify(v));
  }
  function money(v) { return `RM ${Number(v || 0).toFixed(2)}`; }
  function esc(v) {
    return String(v ?? "").replace(/[&<>'"]/g, c => ({
      "&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"
    }[c]));
  }
  function status(p) {
    if (p.refund_status === "refunded") return "Refunded";
    if (p.payment_status === "confirmed") return "Paid";
    if (p.status === "awaiting_payment") return "Payment ready";
    if (p.status === "payment_submitted") return "Payment submitted";
    if (p.status === "delayed") return "Delayed";
    if (p.status === "in_progress") return "In progress";
    return "New order";
  }

  const wrap = document.createElement("div");
  wrap.className = cssClass;
  wrap.innerHTML = `
    <button class="mekyy-cart-fab" id="mekyy-cart-open" aria-label="Open cart">
      <span class="mekyy-cart-icon">🛒</span>
      <span class="mekyy-cart-count" id="mekyy-cart-count">0</span>
    </button>
    <div class="mekyy-cart-popover" id="mekyy-cart-popover" aria-hidden="true">
      <div class="mekyy-cart-head">
        <div>
          <p class="eyebrow">YOUR SPACE</p>
          <h3>Cart & payments</h3>
        </div>
        <button class="mekyy-cart-close" id="mekyy-cart-close" aria-label="Close">×</button>
      </div>
      <div id="mekyy-cart-body"></div>
      <a class="mekyy-cart-history" href="history.html">View full order history →</a>
    </div>`;
  document.body.appendChild(wrap);

  const openBtn = wrap.querySelector("#mekyy-cart-open");
  const pop = wrap.querySelector("#mekyy-cart-popover");
  const closeBtn = wrap.querySelector("#mekyy-cart-close");
  const body = wrap.querySelector("#mekyy-cart-body");
  const count = wrap.querySelector("#mekyy-cart-count");

  async function ensurePricing() {
    if (window.MekyyPricing?.load) return window.MekyyPricing.load();
    return 0;
  }

  async function refresh() {
    try { await ensurePricing(); } catch (_) {}
    const items = window.MekyyPricing ? getCart().map(window.MekyyPricing.normalizeItem) : getCart();
    saveCart(items);
    count.textContent = items.length;
    let active = [];
    try {
      const { data: { user } } = await window.supabaseClient.auth.getUser();
      if (user) {
        const { data: profile } = await window.supabaseClient.from("profiles").select("role").eq("id", user.id).single();
        if (profile?.role === "admin") { wrap.style.display = "none"; return; }
        wrap.style.display = "block";
        const { data } = await window.supabaseClient
          .from("projects")
          .select("id,product,package_name,status,price,refund_status,payment_status,created_at")
          .eq("user_id", user.id)
          .neq("status", "completed")
          .order("created_at", { ascending: false })
          .limit(8);
        active = data || [];
      }
    } catch {}

    const cartHtml = items.length ? `
      <div class="mekyy-cart-section">
        <div class="mekyy-cart-section-title">Saved services</div>
        ${items.map((x,i) => `
          <div class="mekyy-mini-item">
            <div>
              <small>${esc(x.category || "Design Service")}</small>
              <strong>${esc(x.product)}</strong>
              ${x.package ? `<span>${esc(x.package)} · ${money(x.price)}</span>` : ""}
            </div>
            <button data-remove-cart="${i}" aria-label="Remove">×</button>
          </div>`).join("")}
        <button class="btn dark mekyy-cart-start" id="mekyy-start-all">Start selected order${items.length > 1 ? "s" : ""} →</button>
      </div>` : "";

    const paymentOrders = active.filter(p => p.status === "awaiting_payment" || p.status === "payment_submitted");
    const activeHtml = active.length ? `
      <div class="mekyy-cart-section">
        <div class="mekyy-cart-section-title">Active orders</div>
        ${active.map(p => `
          <a class="mekyy-order-mini ${p.status==="awaiting_payment"?"payment-ready":""}" href="chat.html?project=${p.id}#payment">
            <div>
              <strong>${esc(p.product)}${p.package_name?` · ${esc(p.package_name)}`:""}</strong>
              <span>${status(p)}${p.price ? ` · ${money(p.price)}` : ""}</span>
            </div>
            <span>→</span>
          </a>`).join("")}
      </div>` : "";

    body.innerHTML = (cartHtml || activeHtml) ? (cartHtml + activeHtml) : `
      <div class="mekyy-cart-empty">
        <div class="mekyy-empty-icon">✦</div>
        <strong>Nothing here yet.</strong>
        <span>Add a service or open an active order.</span>
        <a class="btn dark" href="index.html#services">Browse services</a>
      </div>`;

    wrap.querySelectorAll("[data-remove-cart]").forEach(btn => {
      btn.onclick = () => {
        const c = getCart();
        c.splice(Number(btn.dataset.removeCart), 1);
        saveCart(c);
        refresh();
      };
    });

    const start = wrap.querySelector("#mekyy-start-all");
    if (start) {
      start.onclick = async () => {
        const { data: { user } } = await window.supabaseClient.auth.getUser();
        if (!user) { location.href = "login.html"; return; }
        try { await ensurePricing(); } catch (_) {}
        const cart = window.MekyyPricing ? getCart().map(window.MekyyPricing.normalizeItem) : getCart();
        saveCart(cart);
        if (!cart.length) return;
        start.disabled = true;
        start.textContent = "Starting…";
        let firstId = null;
        for (const item of cart) {
          const { data, error } = await window.supabaseClient.from("projects").insert({
            user_id: user.id,
            product: item.product,
            package_name: item.package || null,
            title: item.package ? `${item.product} — ${item.package}` : item.product,
            original_price: window.MekyyPricing ? window.MekyyPricing.originalForCart(item) : Number(item.price || 0),
            discount_percent: window.MekyyPricing ? window.MekyyPricing.getDiscount() : 0,
            price: window.MekyyPricing ? window.MekyyPricing.discounted(window.MekyyPricing.originalForCart(item)) : Number(item.price || 0),
            status: "new"
          }).select("id").single();
          if (error) {
            alert(error.message);
            start.disabled = false;
            start.textContent = "Start selected order →";
            return;
          }
          if (!firstId) firstId = data.id;
        }
        saveCart([]);
        location.href = "chat.html?project=" + encodeURIComponent(firstId);
      };
    }
  }

  openBtn.onclick = async () => {
    pop.classList.toggle("open");
    pop.setAttribute("aria-hidden", String(!pop.classList.contains("open")));
    if (pop.classList.contains("open")) await refresh();
  };
  closeBtn.onclick = () => {
    pop.classList.remove("open");
    pop.setAttribute("aria-hidden", "true");
  };
  document.addEventListener("click", e => {
    if (!wrap.contains(e.target)) {
      pop.classList.remove("open");
      pop.setAttribute("aria-hidden", "true");
    }
  });
  window.addEventListener("storage", refresh);
  window.mekyyCartRefresh = refresh;
  refresh();
})();