// Evaluate the shipped browser module with fake React/bridge/InputActions; no network or audio.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import vm from 'node:vm';

const inputIndex = process.argv.indexOf('--client');
const source = readFileSync(inputIndex >= 0 ? process.argv[inputIndex + 1] : new URL('../dsh-plugin/lib/client.js', import.meta.url), 'utf8');
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((yes,no) => {resolve=yes;reject=no;}); return {promise,resolve,reject}; };
const response = value => ({ok:true,json:async()=>value});
function fixture() {
  const hooks = []; let cursor = 0; let module; let mic;
  const calls = []; const starts = []; const clouds = [];
  let revision = 0; let draft = 'SYNTHETIC existing draft'; let submitted = 0;
  const react = {
    useState(initial) { const index=cursor++; if (!(index in hooks)) hooks[index]=initial; return [hooks[index],value=>{hooks[index]=typeof value==='function'?value(hooks[index]):value;}]; },
    useRef(initial) { const index=cursor++; if (!(index in hooks)) hooks[index]={current:initial}; return hooks[index]; },
  };
  const jsx = (type,props) => ({type,props});
  const window = {localStorage:{getItem:()=>null},setTimeout:()=>0,
    __ModuleLoader__:{load(spec){module=spec.factory(name=>name==='react'?react:{jsx,jsxs:jsx});}}};
  vm.runInNewContext(source, {window,crypto:{randomUUID},AbortSignal,
    fetch(url,options) {
      const path = new URL(url).pathname; calls.push({path,body:JSON.parse(options.body)});
      if (path==='/start') { const item=deferred(); starts.push(item); return item.promise; }
      if (path==='/stop') return Promise.resolve(response({}));
      if (path==='/transcribe-cloud') { const item=deferred(); clouds.push(item); return item.promise; }
      throw new Error('Unexpected synthetic route');
    }});
  module.apply({slots:{inject:(name,fn)=>fn(),register:(slot,component)=>{if(slot.name==='conversation.composer.dock')mic=component;return()=>{};}}});
  const actions = {
    captureInsertion:()=>({revision}),
    insertText(text,span){if(span.revision!==revision)return false;draft+=' '+text;revision++;return true;},
    submit(){submitted++;throw new Error('Must not send');},
    setDraft(){throw new Error('Must not overwrite');},
  };
  return {calls,starts,clouds,actions,render(){cursor=0;return mic({inputActions:actions}).props.children[0].props;},
    edit(){draft+=' SYNTHETIC manual edit';revision++;},draft:()=>draft,submitted:()=>submitted};
}
const tests = [];
const item = fixture();
const idle = item.render(); idle.onClick(); idle.onClick(); idle.onClick();
assert.equal(item.starts.length,1);
assert.equal(item.render().disabled,true);
item.starts[0].resolve(response({recordingId:'SYNTHETIC-recording'})); await tick();
assert.equal(item.render().disabled,false);
tests.push('rapid-start-clicks-send-one-request-before-react-render');
item.edit();
const recording = item.render(); recording.onClick(); recording.onClick();
await tick();
assert.equal(item.calls.filter(call=>call.path==='/stop').length,1);
assert.equal(item.clouds.length,1);
assert.equal(item.render().disabled,true);
item.clouds[0].resolve(response({text:'SYNTHETIC cleaned text'})); await tick();
assert.match(item.draft(),/existing draft SYNTHETIC manual edit SYNTHETIC cleaned text/);
assert.equal(item.submitted(),0);
assert.equal(item.render().disabled,false);
tests.push('rapid-stop-guard-and-stale-draft-preservation-without-submit');
const failure = fixture(); failure.render().onClick();
failure.starts[0].reject(new Error('Synthetic start failure')); await tick();
assert.equal(failure.render().disabled,false);
failure.render().onClick(); assert.equal(failure.starts.length,2);
failure.starts[1].resolve(response({recordingId:'SYNTHETIC-retry'})); await tick();
tests.push('failed-start-releases-lock-for-retry');
const captureFailure = fixture();
captureFailure.actions.captureInsertion=()=>{throw new Error('Synthetic editor lock');};
captureFailure.render().onClick(); await tick();
assert.equal(captureFailure.starts.length,0);
assert.equal(captureFailure.render().disabled,false);
tests.push('capture-failure-releases-lock-without-recording');
console.log(JSON.stringify({ok:true,tests,real_cloud_calls:0,microphone_used:false}));
