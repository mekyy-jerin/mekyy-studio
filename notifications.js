/* MekyyStudio V21 in-page notifications. No browser alert popups. */
(function(){
  function esc(v){return String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}
  function ensure(){
    let el=document.getElementById('mekyy-toasts');
    if(!el){el=document.createElement('div');el.id='mekyy-toasts';el.className='mekyy-toasts';document.body.appendChild(el);}
    return el;
  }
  function show(message,type='info',timeout=4200){
    const el=ensure(), toast=document.createElement('div');
    toast.className='mekyy-toast '+type;
    toast.innerHTML='<span>'+esc(message)+'</span><button type="button" aria-label="Close">×</button>';
    toast.querySelector('button').onclick=()=>toast.remove();
    el.appendChild(toast);
    if(timeout>0)setTimeout(()=>toast.remove(),timeout);
  }
  async function loadUnread(supabase,userId){
    if(!supabase||!userId)return [];
    const {data}=await supabase.from('notifications').select('id,title,body,type,created_at,read').eq('user_id',userId).eq('read',false).order('created_at',{ascending:false}).limit(20);
    return data||[];
  }
  async function markRead(supabase,id){if(supabase&&id)await supabase.from('notifications').update({read:true}).eq('id',id);}
  window.MekyyNotify={show,ensure,loadUnread,markRead};
})();
