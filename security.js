/* V21: watermark outgoing preview images so chat previews cannot be mistaken for final files. */
(function(){
  async function watermarkImage(file,text='MEKYYSTUDIO • PREVIEW'){
    if(!file||!file.type.startsWith('image/'))return file;
    const img=new Image(), url=URL.createObjectURL(file);
    try{
      await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;img.src=url;});
      const max=2400, scale=Math.min(1,max/Math.max(img.naturalWidth,img.naturalHeight));
      const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.naturalWidth*scale));canvas.height=Math.max(1,Math.round(img.naturalHeight*scale));
      const ctx=canvas.getContext('2d');ctx.drawImage(img,0,0,canvas.width,canvas.height);
      const size=Math.max(18,Math.round(canvas.width/28));
      ctx.save();ctx.globalAlpha=.28;ctx.fillStyle='#ffffff';ctx.font=`700 ${size}px Arial`;ctx.textAlign='center';ctx.textBaseline='middle';ctx.translate(canvas.width/2,canvas.height/2);ctx.rotate(-Math.PI/7);
      const step=size*4;for(let y=-canvas.height;y<canvas.height;y+=step)for(let x=-canvas.width;x<canvas.width;x+=step)ctx.fillText(text,x,y);
      ctx.restore();
      const blob=await new Promise(r=>canvas.toBlob(r,file.type==='image/png'?'image/png':'image/jpeg',.9));
      if(!blob)return file;
      const name=file.name.replace(/\.[^.]+$/,'')+'-preview.'+(file.type==='image/png'?'png':'jpg');
      return new File([blob],name,{type:blob.type,lastModified:Date.now()});
    }finally{URL.revokeObjectURL(url);}
  }
  window.MekyySecurity={watermarkImage};
})();
