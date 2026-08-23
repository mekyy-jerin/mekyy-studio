/* MekyyStudio V18 — shared pricing + scheduled discount */
(function () {
  const state = { percent: 0, start: "", end: "", enabled: false, loaded: false };

  function parseSetting(value) {
    if (!value) return null;
    try { return typeof value === "string" ? JSON.parse(value) : value; } catch (_) { return null; }
  }
  function activeNow(d) {
    if (!d || !d.enabled) return false;
    const percent = Number(d.percent);
    if (!Number.isFinite(percent) || percent <= 0) return false;
    const now = new Date();
    if (d.start && now < new Date(d.start + "T00:00:00")) return false;
    if (d.end && now > new Date(d.end + "T23:59:59")) return false;
    return true;
  }
  async function load() {
    state.percent=0; state.start=""; state.end=""; state.enabled=false;
    // No discount is a valid/default state. Never block the catalog.
    try {
      if (!window.supabaseClient) { state.loaded=true; return 0; }
      const {data,error}=await window.supabaseClient.from("site_settings").select("value").eq("key","store_discount").maybeSingle();
      if(!error && data){
        const d=parseSetting(data.value)||{};
        state.percent=Math.min(100,Math.max(0,Number(d.percent)||0));
        state.start=d.start||""; state.end=d.end||""; state.enabled=!!d.enabled;
      }
    } catch (_) {}
    state.loaded=true;
    return api.getDiscount();
  }
  function getDiscount(){return activeNow(state)?state.percent:0;}
  function discounted(price){
    const original=Number(price)||0, d=getDiscount();
    return d?Math.round(original*(1-d/100)*100)/100:original;
  }
  function originalForCart(item){
    if(item && Number.isFinite(Number(item.originalPrice))) return Number(item.originalPrice);
    const catalog=window.MEKYY_PACKAGES?.[item?.product]?.[item?.package]?.price;
    return catalog!=null?Number(catalog):Number(item?.price||0);
  }
  function normalizeItem(item){
    const original=originalForCart(item);
    return {...item,originalPrice:original,price:discounted(original),discount:getDiscount()};
  }
  function money(v){return "RM "+Number(v||0).toFixed(2);}
  function priceHTML(price){
    const original=Number(price)||0, finalPrice=discounted(original), d=getDiscount();
    if(!d) return `<div class="price-box"><div class="price-new">${money(original)}</div></div>`;
    return `<div class="price-box"><span class="price-old">${money(original)}</span><span class="price-new">${money(finalPrice)}</span><span class="discount-badge">${d}% OFF</span><div class="discount-info">Limited-time studio discount</div></div>`;
  }
  const api={state,load,getDiscount,discounted,normalizeItem,originalForCart,money,priceHTML,isActive:()=>getDiscount()>0};
  window.MekyyPricing=api;
})();
