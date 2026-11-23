const fs=require('fs'),vm=require('vm'),assert=require('assert');
const handlers=new Map();let context,stopped=0,processed=0;
class AudioContext {
 constructor(){context=this;this.state='suspended';this.sampleRate=48000}
 resume(){return new Promise(resolve=>{this.resolve=()=>{this.state='running';this.onstatechange?.();resolve()}})}
 createMediaStreamSource(){return {connect(){},disconnect(){}}}
 createScriptProcessor(){processed++;return {connect(){},disconnect(){}}}
 createGain(){return {gain:{},connect(){},disconnect(){}}}
 close(){this.state='closed';return Promise.resolve()}
}
const window={addEventListener:(type,fn)=>handlers.set(type,fn),removeEventListener:(type,fn)=>{if(handlers.get(type)===fn)handlers.delete(type)}};
const sandbox={window,AudioContext,navigator:{mediaDevices:{getUserMedia:async()=>({getTracks:()=>[{stop(){stopped++}}]})}},performance:{now:()=>0},Map,Uint8Array,Float32Array,Int16Array,Math,JSON};
vm.runInNewContext(fs.readFileSync('web/beta_audio.js','utf8'),sandbox);
(async()=>{
 const events=[];const id=window.betaAudioCreate((...e)=>events.push(e),async()=>'{"text":""}');
 await window.betaAudioListen(id,'asleep');
 assert.equal(processed,1);assert.deepEqual(events.at(-1),['state','waiting']);
 assert(handlers.has('pointerdown'));handlers.get('pointerdown')();context.resolve();
 assert.deepEqual(events.at(-1),['state','listening']);
 window.betaAudioStop(id);assert(!handlers.has('pointerdown'));assert(!handlers.has('keydown'));assert.equal(stopped,1);
 window.betaAudioDispose(id);
 console.log('PASS: suspended audio does not stall capture; trusted interaction resumes; listeners and mic cleaned');
})().catch(e=>{console.error(e);process.exitCode=1});
