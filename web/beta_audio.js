(() => {
 'use strict';
 let next=0;const clients=new Map();
 const encode=buffer=>{const data=new Uint8Array(buffer);let binary='';for(let i=0;i<data.length;i+=8192)binary+=String.fromCharCode(...data.subarray(i,i+8192));return btoa(binary)};
 const active=id=>clients.get(id);
 function fixedManifest(){
   if(typeof document==='undefined'||typeof fetch!=='function')return Promise.resolve({});
   return fetch(new URL('beta-voice/manifest.json',document.baseURI),{cache:'force-cache',signal:AbortSignal.timeout(3000)})
     .then(r=>r.ok?r.json():{}).catch(()=>({}));
 }
 async function fixedClip(client,text){
   const manifest=await client.fixedManifest;
   if(!Object.prototype.hasOwnProperty.call(manifest,text)||!/^\w{20}\.wav$/.test(manifest[text]))return null;
   try{
     const response=await fetch(new URL('beta-voice/'+manifest[text],document.baseURI),{cache:'force-cache',signal:AbortSignal.timeout(3000)});
     if(!response.ok)return null;
     const data=await response.arrayBuffer();
     if(data.byteLength<44||data.byteLength>2000000||new DataView(data).getUint32(0)!==0x52494646)return null;
     return new Blob([data],{type:'audio/wav'});
   }catch{return null}
 }
 function stop(client){
   if(!client)return;client.epoch++;
   if(client.unlock){window.removeEventListener('pointerdown',client.unlock,true);window.removeEventListener('keydown',client.unlock,true);client.unlock=null}
   if(client.context)client.context.onstatechange=null;
   if(client.speaking){client.speaking=false;window.betaSpeechBusy=false;window.betaSpeechQuietUntil=performance.now()+600}
   if(client.processor){client.processor.onaudioprocess=null;client.processor.disconnect();client.processor=null}
   client.source?.disconnect();client.gain?.disconnect();client.stream?.getTracks().forEach(t=>t.stop());
   client.context?.close().catch(()=>{});client.context=null;
   if(client.audio){client.audio.pause();client.audio.removeAttribute('src');client.audio.load();client.audio=null}
   if(client.url){URL.revokeObjectURL(client.url);client.url=null}
   client.finish?.();client.finish=null;
 }
 window.betaAudioCreate=(event,transport)=>{const id=++next;clients.set(id,{event,transport,epoch:0,fixedManifest:fixedManifest()});return id};
 window.betaAudioStop=id=>stop(active(id));
 window.betaAudioDispose=id=>{stop(active(id));clients.delete(id)};
 window.betaAudioListen=async(id,mode)=>{
   const client=active(id);if(!client)return;stop(client);const epoch=client.epoch;
   const current=()=>active(id)===client&&client.epoch===epoch;
   try{
     const stream=await navigator.mediaDevices.getUserMedia({audio:{channelCount:1,echoCancellation:true,noiseSuppression:true}});
     if(!current()){stream.getTracks().forEach(t=>t.stop());return}
     client.stream=stream;client.context=new AudioContext();
     // Autoplay policy can leave resume pending until a trusted interaction.
     // Install capture and unlock handlers without waiting on that promise.
     client.unlock=()=>{if(current()&&client.context.state==='suspended')client.context.resume().catch(()=>{})};
     window.addEventListener('pointerdown',client.unlock,true);window.addEventListener('keydown',client.unlock,true);
     client.context.onstatechange=()=>{if(current())client.event('state',client.context.state==='running'?'listening':'waiting')};
     client.unlock();
     const context=client.context,source=context.createMediaStreamSource(stream),processor=context.createScriptProcessor(4096,1,1),gain=context.createGain();
     client.source=source;client.processor=processor;client.gain=gain;gain.gain.value=0;source.connect(processor);processor.connect(gain);gain.connect(context.destination);
     let chunks=[],samples=0,quiet=0,speech=false,pending=false;
     processor.onaudioprocess=async event=>{
       if(!current()||pending)return;const input=event.inputBuffer.getChannelData(0);let energy=0;for(const v of input)energy+=v*v;
       if(Math.sqrt(energy/input.length)>.006){speech=true;quiet=0}else quiet+=input.length;
       chunks.push(new Float32Array(input));samples+=input.length;
       if(!speech&&samples>context.sampleRate){chunks=chunks.slice(-2);samples=chunks.reduce((s,c)=>s+c.length,0)}
       if(!speech||!(quiet>context.sampleRate*.6||samples>context.sampleRate*8))return;
       pending=true;const pcm=new Int16Array(samples);let offset=0;for(const chunk of chunks)for(const v of chunk)pcm[offset++]=Math.round(Math.max(-1,Math.min(1,v))*32767);
       try{
         const result=JSON.parse(await client.transport(JSON.stringify({action:'recognize',pcm:encode(pcm.buffer),sampleRate:context.sampleRate,mode})));
         if(!current())return;
         if(result.text){stop(client);client.event('text',result.text);return}
         chunks=[];samples=0;quiet=0;speech=false;pending=false;
       }catch(error){if(current()){stop(client);client.event('error','Não consegui reconhecer a fala local. Verifique a integração e ative a escuta novamente.')}}
     };
     client.event('state',context.state==='running'?'listening':'waiting');
   }catch(error){if(current()){stop(client);client.event('error',error.name==='NotAllowedError'?'Permita o microfone nas configurações deste site.':'Não consegui acessar o microfone deste computador.')}}
 };
 window.betaAudioSpeak=async(id,text)=>{
   const client=active(id);if(!client)return;stop(client);const epoch=client.epoch;
   client.speaking=true;window.betaSpeechBusy=true;
   const current=()=>active(id)===client&&client.epoch===epoch;
   try{
     let clip=await fixedClip(client,text);
     if(!current())return;
     if(!clip){
       const response=JSON.parse(await client.transport(JSON.stringify({action:'speech',text,speed:.98})));
       if(!current())return;
       const bytes=Uint8Array.from(atob(response.audio),c=>c.charCodeAt(0));clip=new Blob([bytes],{type:'audio/wav'});
     }
     if(!current())return;
     client.url=URL.createObjectURL(clip);
     const audio=new Audio(client.url);client.audio=audio;
     await new Promise((resolve,reject)=>{client.finish=resolve;audio.onended=resolve;audio.onerror=()=>reject(new Error('Não consegui reproduzir a voz Dora.'));audio.play().catch(reject)});
   }
   finally{if(current())stop(client)}
 };
 window.addEventListener('pagehide',()=>clients.forEach(stop));
})();
