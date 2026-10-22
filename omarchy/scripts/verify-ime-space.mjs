#!/usr/bin/env node
// Native E2E: real Waynergy -> Hyprland -> Fcitx5 -> a disposable Chrome editor.
// Requires native Fcitx Ctrl+Space, a keyboard-us/hangul group and Node >= 22.
// Briefly stops the live Waynergy service and restores it, focus and input mode.
import {mkdtempSync, writeFileSync, readFileSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawn, spawnSync, execFileSync} from 'node:child_process';
import net from 'node:net';

const sleep = ms => new Promise(r => setTimeout(r, ms));
const run = (...args) => execFileSync(args[0], args.slice(1), {encoding:'utf8',timeout:10000}).trim();
const assert = (condition, message) => {if (!condition) throw Error(message);};
const focus = address => {
 assert(/^0x[0-9a-f]+$/i.test(address),'Invalid window address');
 assert(run('hyprctl','eval',`hl.dispatch(hl.dsp.focus({window="address:${address}"}))`)==='ok','Could not focus window');
};
const within = (promise, ms, message) => {
 let timer;
 return Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error(message)),ms);})])
  .finally(()=>clearTimeout(timer));
};
const root = mkdtempSync(join(tmpdir(),'waynergy-ime-check-'));
const previousWindow = JSON.parse(run('hyprctl','-j','activewindow')).address;
const previousIM = run('fcitx5-remote','-n');
const live = spawnSync('systemctl',['--user','is-active','--quiet','waynergy.service']).status === 0;
const html = `<!doctype html><meta charset="utf-8"><title>Waynergy 입력 검사</title>
<h1>Waynergy 입력 검사</h1><p>자동 입력 검사 중입니다. 창이 닫힐 때까지 기다려 주세요.</p>
<div id="editor" contenteditable="true" style="border:1px solid;padding:20px;min-height:200px"></div>
<script>window.events=[]; for(const type of ['keydown','keyup','input','compositionstart','compositionend'])
document.addEventListener(type,e=>events.push({type,code:e.code,key:e.key,repeat:e.repeat,time:performance.now()}));
editor.focus();</script>`;
writeFileSync(join(root,'index.html'),html);
writeFileSync(join(root,'config.ini'),'[idle-inhibit]\nenable=false\n[raw-keymap]\noffset=8\n');
let chrome, client, socket, ws, server, ownWindow, stoppedLive=false, interrupted=false;
for (const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>{interrupted=true;});
let serial=0;
const pending = new Map();
async function evaluate(expression) {
 const id=++serial;
 const response=new Promise((resolve,reject)=>pending.set(id,{resolve,reject}));
 ws.send(JSON.stringify({id,method:'Runtime.evaluate',params:{expression,returnByValue:true}}));
 const result=await within(response,5000,'Chrome evaluation timed out');
 assert(!result.error && !result.result?.exceptionDetails, 'Chrome evaluation failed');
 return result.result.result.value;
}
function packet(body) {const length=Buffer.alloc(4);length.writeUInt32BE(body.length);socket.write(Buffer.concat([length,body]));}
async function key(raw,down) {
 if(down) {
  assert(!interrupted,'Input check interrupted');
  assert(JSON.parse(run('hyprctl','-j','activewindow')).address===ownWindow,'Test window lost focus; stopping input');
 }
 const b=Buffer.alloc(10);b.write(down?'DKDN':'DKUP');
 const id=raw===57?32:raw===42?0xffe1:raw===29?0xffe3:raw===30?97:raw===14?0xff08:raw===48?98:raw===37?107:114;
 b.writeUInt16BE(id,4);b.writeUInt16BE(0,6);b.writeUInt16BE(raw,8);packet(b);
}
async function sequence(actions) {for(const [raw,down,delay=35] of actions){await key(raw,down);await sleep(delay);}}
async function reset() {
 for (const raw of [57,42,29,30,48]) await key(raw,false);
 await sequence([[30,true],[30,false]]); await sleep(150);
 await evaluate(`editor.textContent="";events=[];editor.focus();
  {const r=document.createRange();r.selectNodeContents(editor);r.collapse(false);
   const s=getSelection();s.removeAllRanges();s.addRange(r);}`);
}
try {
 chrome=spawn('/usr/bin/google-chrome-stable',[
  '--user-data-dir='+join(root,'chrome'),'--remote-debugging-port=0','--no-first-run',
  '--no-default-browser-check','--ozone-platform=wayland','--enable-wayland-ime',
  '--wayland-text-input-version=3','--app=file://'+join(root,'index.html'),
 ],{stdio:'ignore'});
 for(let i=0;i<150&&!existsSync(join(root,'chrome','DevToolsActivePort'));i++) await sleep(100);
 const port=readFileSync(join(root,'chrome','DevToolsActivePort'),'utf8').split('\n')[0];
 let targets=[];
 for(let i=0;i<100;i++){
  targets=await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  if(targets.some(t=>t.type==='page'))break;
  await sleep(100);
 }
 ws=new WebSocket(targets.find(t=>t.type==='page').webSocketDebuggerUrl);
 await within(new Promise((r,j)=>{ws.onopen=r;ws.onerror=j}),5000,'Chrome debugger connection timed out');
 ws.onmessage=event=>{const x=JSON.parse(event.data);if(pending.has(x.id)){pending.get(x.id).resolve(x);pending.delete(x.id)}};
 for(let i=0;i<100;i++){
  const window=JSON.parse(run('hyprctl','-j','clients')).find(c=>c.pid===chrome.pid && c.title==='Waynergy 입력 검사');
  if(window){ownWindow=window.address;break;}
  await sleep(50);
 }
 assert(ownWindow,'Could not identify the disposable Chrome window');
 focus(ownWindow);
 await evaluate('editor.focus()');
 if(live){run('systemctl','--user','stop','waynergy.service');stoppedLive=true;}
 const connected = new Promise(resolve=>{
  server=net.createServer(s=>{socket=s;resolve(s)}).listen(0,'127.0.0.1');
 });
 while(!server.listening)await sleep(5);
 client=spawn('/usr/bin/waynergy',['-c','127.0.0.1','-p',String(server.address().port),'-N','ime-check','-E','-n','-L','none'],
  {env:{...process.env,WAYNERGY_CONF_PATH:root},stdio:'ignore'});
 await within(connected,10000,'Waynergy loopback connection timed out');
 let received=Buffer.alloc(0);socket.on('data',chunk=>{received=Buffer.concat([received,chunk])});
 packet(Buffer.concat([Buffer.from('Deskflow'),Buffer.from([0,1,0,8])]));
 for(let i=0;i<100&&received.length===0;i++)await sleep(20);
 if(received.length===0)throw Error('No client handshake');
 const enter=Buffer.alloc(14);enter.write('CINN');enter.writeInt16BE(100,4);enter.writeInt16BE(100,6);enter.writeUInt32BE(1,8);packet(enter);
 await sleep(300);
 assert(JSON.parse(run('hyprctl','-j','activewindow')).address===ownWindow,'Test window is not focused');
 const cases=[
  ['tap',[[57,true],[57,false]]],
  ['shift-space:space-up-first',[[42,true],[57,true],[57,false],[42,false]]],
  ['shift-space:shift-up-first',[[42,true],[57,true],[42,false],[57,false]]],
  ['space-overlap-shift',[[57,true],[42,true],[57,false],[42,false]]],
  ['ctrl-space:space-up-first',[[29,true],[57,true],[57,false],[29,false]]],
  ['ctrl-space:ctrl-up-first',[[29,true],[57,true],[29,false],[57,false]]],
  ['ctrl-space:held',[[29,true],[57,true,600],[57,false],[29,false]]],
  ['space-overlap-ctrl',[[57,true],[29,true],[57,false],[29,false]]],
  ['space:held',[[57,true,600],[57,false]]],
 ];
 for (const [name,actions] of cases) {
  await reset();run('fcitx5-remote','-s','keyboard-us');await sleep(100);
  await sequence(actions);await sleep(650);
  const a=await evaluate('({text:editor.textContent,events})');
  const size=a.text.length;await sleep(350);
  const b=await evaluate('({text:editor.textContent,events})');
  const spaces=[...b.text].filter(x=>x===' '||x==='\u00a0').length;
  console.log(JSON.stringify({name,spaceCount:spaces,lateGrowth:b.text.length-size,im:run('fcitx5-remote','-n')}));
  if (b.text.length!==size)throw Error(name+': repeat continued after release');
  if (name.startsWith('ctrl-space:') && spaces!==0)throw Error(name+': trigger leaked a space');
  if (name.startsWith('ctrl-space:') && name!=='ctrl-space:held' && run('fcitx5-remote','-n')!=='hangul')throw Error(name+': native trigger failed');
  if (name==='tap'&&spaces!==1)throw Error('A single space did not produce exactly one space');
  if (!name.startsWith('ctrl-space:') && name!=='space:held' && spaces!==1)throw Error(name+': expected one space');
  // Fcitx intentionally accepts repeated trigger presses while Ctrl is held.
  // The held-trigger contract is no leaked space and no repetition after release.
  if (name==='space:held'&&spaces<2)throw Error('Holding space no longer repeats');
 }
 await reset();run('fcitx5-remote','-s','keyboard-us');await sleep(100);
 for (let cycle=0;cycle<24;cycle++) {
  await sequence([[29,true],[57,true],...(cycle%2?[[29,false],[57,false]]:[[57,false],[29,false]])]);
  assert(run('fcitx5-remote','-n')===(cycle%2?'keyboard-us':'hangul'),'Input mode did not alternate during stress');
  await sequence([[19,true],[19,false],[37,true],[37,false],[57,true],[57,false]]);
  if(cycle%6===5){
   const before=await evaluate('editor.textContent.length');await sleep(400);
   if(await evaluate('editor.textContent.length')!==before)throw Error('Repeat continued during switch/typing stress');
  }
 }
 console.log('PASS: 24 native Ctrl+Space switches with alternating key release order and Korean/English input');
} finally {
 try { if(socket){await sequence([[57,false],[42,false],[29,false],[30,true],[30,false]]);packet(Buffer.from('COUT'));await sleep(100);} }catch{}
 client?.kill();socket?.destroy();server?.close();ws?.close();chrome?.kill();
 if(stoppedLive)run('systemctl','--user','start','waynergy.service');
 if(previousWindow)try{focus(previousWindow)}catch{}
 try{run('fcitx5-remote','-s',previousIM)}catch{}
 console.log('test_directory='+root);
}
