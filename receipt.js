/* V21 custom customer receipt. Attempts a PDF download, then falls back to HTML. */
(function(){
  function esc(v){return String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}
  function html(project){
    const date=new Date(project.payment_confirmed_at||new Date()).toLocaleString();
    return `<!doctype html><html><head><meta charset="utf-8"><title>MekyyStudio Receipt</title><style>body{font-family:Arial,sans-serif;padding:42px;color:#17191c}main{max-width:680px;margin:auto;border:1px solid #ddd;padding:36px}h1{font-size:30px}small{color:#777}table{width:100%;margin-top:28px;border-collapse:collapse}td{padding:12px;border-bottom:1px solid #eee}.total{font-size:22px;font-weight:700;text-align:right;margin-top:24px}.paid{display:inline-block;padding:7px 10px;border-radius:99px;background:#dff1e5;color:#24613c;font-weight:700}</style></head><body><main><small>MEKYYSTUDIO</small><h1>Payment Receipt</h1><span class="paid">PAID</span><table><tr><td>Order</td><td>${esc(project.product)}</td></tr><tr><td>Package</td><td>${esc(project.package_name||'')}</td></tr><tr><td>Payment method</td><td>${esc(project.payment_method||'')}</td></tr><tr><td>Payment date</td><td>${esc(date)}</td></tr><tr><td>Order ID</td><td>#${esc(project.id)}</td></tr></table><div class="total">RM ${Number(project.price||0).toFixed(2)}</div><p>Thank you for choosing MekyyStudio.</p></main></body></html>`;
  }
  async function download(project,force=false){
    if(!project||project.payment_status!=='confirmed')return false;
    const key='mekyy-receipt-'+project.id;
    if(!force&&localStorage.getItem(key))return false;
    try{
      if(window.jspdf?.jsPDF){const {jsPDF}=window.jspdf;const doc=new jsPDF();doc.setFontSize(20);doc.text('MekyyStudio',20,22);doc.setFontSize(16);doc.text('Payment Receipt',20,34);doc.setFontSize(11);doc.text('PAID',20,47);const rows=[['Order',String(project.product||'')],['Package',String(project.package_name||'')],['Payment method',String(project.payment_method||'')],['Payment date',new Date(project.payment_confirmed_at||new Date()).toLocaleString()],['Order ID','#'+project.id],['Total','RM '+Number(project.price||0).toFixed(2)]];let y=64;for(const [a,b] of rows){doc.text(a,20,y);doc.text(b,75,y);y+=12;}doc.save(`MekyyStudio-Receipt-${project.id}.pdf`);}
      else{const blob=new Blob([html(project)],{type:'text/html'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`MekyyStudio-Receipt-${project.id}.html`;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);}
      localStorage.setItem(key,'1');return true;
    }catch(e){return false;}
  }
  window.MekyyReceipt={download,html};
})();
