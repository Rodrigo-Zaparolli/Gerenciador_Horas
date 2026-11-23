const fs=require('fs'),vm=require('vm'),assert=require('assert');
async function check(fixed,broken=false){
 const events=[];let calls=0,plays=0;
 const wav=new Uint8Array(44);wav.set([82,73,70,70]);
 class Audio{play(){plays++;queueMicrotask(()=>this.onended?.());return Promise.resolve()}pause(){}removeAttribute(){}load(){}}
 class AssetURL extends URL{static createObjectURL(){return 'blob:voice'}static revokeObjectURL(){}}
 const window={addEventListener(){},removeEventListener(){}};
 const sandbox={window,document:{baseURI:'https://example.test/piloto/'},fetch:async url=>{
  assert(url.pathname.startsWith('/piloto/beta-voice/'));
  if(broken)throw Error('offline');
  if(url.pathname.endsWith('manifest.json'))return {ok:true,json:async()=>({'hello':'12345678901234567890.wav'})};
  return {ok:true,arrayBuffer:async()=>wav.buffer};
 },URL:AssetURL,Blob,Audio,AbortSignal,DataView,Uint8Array,Map,JSON,performance:{now:()=>0},atob,btoa};
 vm.runInNewContext(fs.readFileSync('web/beta_audio.js','utf8'),sandbox);
 const id=window.betaAudioCreate((...e)=>events.push(e),async raw=>{calls++;assert.equal(JSON.parse(raw).action,'speech');return JSON.stringify({audio:btoa('RIFF'+''.padEnd(40,'x'))})});
 await window.betaAudioSpeak(id,fixed?'hello':'live project data');
 assert.equal(calls,fixed&&!broken?0:1);assert.equal(plays,1);assert.equal(window.betaSpeechBusy,false);
 window.betaAudioDispose(id);
}
(async()=>{await check(true);await check(false);await check(true,true);console.log('PASS: fixed prompt bypasses synthesis; live text and unavailable assets use native voice; echo guard cleared')})().catch(e=>{console.error(e);process.exitCode=1});
