/* Two independent documents. The right pane never edits the left pane. */
window.ExternalComparison = class {
  constructor(post, revision) {
    this.post=post;this.revision=revision;this.jobs=new Map();this.sequence=0;
    const workerSource=`const compare=${comparisonDiff.toString()};onmessage=e=>{const {id,base,other}=e.data;postMessage({id,ops:compare(base,other)})}`;
    const workerURL=URL.createObjectURL(new Blob([workerSource],{type:'text/javascript'}));
    this.worker=new Worker(workerURL);URL.revokeObjectURL(workerURL);
    this.worker.onmessage=event=>{const job=this.jobs.get(event.data.id);this.jobs.delete(event.data.id);job?.(event.data.ops)};
    this.worker.onerror=()=>{this.failed=true;this.rightBody.textContent='Comparison could not be displayed. Your text and the disk version are preserved.';this.jobs.clear()};
    const root=document.createElement('div');root.id='native-workspace';
    const left=document.createElement('section');left.id='native-local-pane';
    for(const child of [...document.body.children])if(child.tagName!=='SCRIPT')left.appendChild(child);
    root.appendChild(left);document.body.appendChild(root);
    this.left=left;this.root=root;
    this.localToast=this.banner('Your local version is preserved.','Save my version as…',()=>post({type:'saveLocalAs'}));
    this.localToast.id='native-local-toast';this.localToast.hidden=true;left.prepend(this.localToast);
    this.right=document.createElement('aside');this.right.id='native-disk-pane';this.right.hidden=true;
    const header=this.banner('File changed outside the app.','Apply changes?',()=>post({type:'applyExternal',token:this.token}));
    this.apply=header.querySelector('button');this.right.appendChild(header);
    const label=document.createElement('div');label.className='native-comparison-label';label.textContent='Disk version · Markdown · yellow: added · red: removed';this.right.appendChild(label);
    this.rightBody=document.createElement('pre');this.rightBody.id='native-disk-diff';this.rightBody.tabIndex=0;this.rightBody.setAttribute('aria-label','External Markdown changes');
    this.right.appendChild(this.rightBody);root.appendChild(this.right);
  }
  banner(text,label,action) {
    const bar=document.createElement('div');bar.className='native-comparison-toast';bar.setAttribute('role','status');
    const message=document.createElement('span');message.textContent=text;bar.appendChild(message);
    const button=document.createElement('button');button.textContent=label;button.onclick=action;bar.appendChild(button);return bar;
  }
  diff(base,other,callback) {
    if(this.failed)return;
    const id=++this.sequence;this.jobs.set(id,callback);this.worker.postMessage({id,base,other});
  }
  show({base,disk,token,issue}) {
    this.base=base;this.token=token;this.shown=true;
    this.localToast.hidden=false;this.right.hidden=false;document.documentElement.classList.add('native-comparing');
    this.apply.disabled=true;
    const shownToken=token;
    if(issue)this.rightBody.textContent=issue;
    else {
      this.rightBody.textContent='Comparing external changes…';
      this.diff(base.split('\n'),disk.split('\n'),ops=>{
        if(this.token!==shownToken||!this.shown)return;
        const fragment=document.createDocumentFragment();
        for(const op of ops) {
          const element=document.createElement(op.type==='delete'?'del':'span');
          element.className='native-diff-'+op.type;element.textContent=op.values.join('\n')+'\n';fragment.appendChild(element);
        }
        this.rightBody.replaceChildren(fragment);this.apply.disabled=false;
      });
    }
    this.scheduleLocal();
  }
  clear() {
    this.shown=false;this.token=null;clearTimeout(this.localTimer);
    this.localToast.hidden=true;this.right.hidden=true;document.documentElement.classList.remove('native-comparing');
    this.jobs.clear();window.__mdEditorBridge.clearComparisonDecorations?.();
  }
  scheduleLocal() {
    if(!this.shown)return;
    clearTimeout(this.localTimer);this.localTimer=setTimeout(()=>this.localDiff(),650);
  }
  localDiff() {
    if(!this.shown)return;
    const api=window.__mdEditorBridge, version=this.revision(), token=this.token;
    const data=api.comparisonUnits(this.base);
    const base=data.mode==='source'?data.base:data.base.map(u=>u.key);
    const current=data.mode==='source'?data.current:data.current.map(u=>u.key);
    this.diff(base,current,ops=>{
      if(!this.shown||this.token!==token)return;
      if(this.revision()!==version||api.activeState().mode!==data.mode){this.scheduleLocal();return}
      const specs=[];let cursor=0;
      const offsets=[1];if(data.mode==='source')for(const line of data.current)offsets.push(offsets[offsets.length-1]+line.length+1);
      for(let index=0;index<ops.length;index++) {
        const op=ops[index];if(op.type==='equal'){cursor+=op.values.length;continue}
        const removed=[],added=[];
        while(index<ops.length&&ops[index].type!=='equal') {
          const change=ops[index];
          if(change.type==='delete'){for(let j=change.start;j<change.end;j++)removed.push(data.base[j])}
          else {for(let j=cursor;j<cursor+change.values.length;j++)added.push(data.current[j]);cursor+=change.values.length}
          index++;
        }
        index--;
        const start=cursor-added.length;
        if(data.mode==='source') {
          specs.push({from:offsets[start],to:Math.max(offsets[start],(offsets[cursor]??offsets[start])-1),deleted:removed.join('\n')});
        } else {
          for(let i=0;i<Math.max(removed.length,added.length);i++) {
            const old=removed[i],next=added[i];
            if(next?.inline&&old?.inline&&old.kind===next.kind&&old.text!==next.text) {
              let p=0,s=0;while(p<old.text.length&&p<next.text.length&&old.text[p]===next.text[p])p++;
              while(s<old.text.length-p&&s<next.text.length-p&&old.text[old.text.length-1-s]===next.text[next.text.length-1-s])s++;
              specs.push({from:next.from+1+p,to:next.from+1+next.text.length-s,deleted:old.text.slice(p,old.text.length-s)});
            } else if(next)specs.push({from:next.inline?next.from+1:next.from,to:next.inline?next.to-1:next.to,node:!next.inline,deleted:old&&old.text!==next.text?old.text:''});
            else if(old)specs.push({from:data.current[cursor]?.from??Math.max(0,(data.current.at(-1)?.to??1)-1),deleted:old.text});
          }
        }
      }
      api.setComparisonDecorations(specs);
    });
  }
};
