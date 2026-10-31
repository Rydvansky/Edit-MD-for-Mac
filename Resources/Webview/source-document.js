/* Keep Markdown as the source of truth. The rich editor is a projection, not a
   formatter for the whole file. Unchanged blocks retain their original bytes,
   including unsupported syntax, reference definitions and whitespace. */
window.SourceDocument = class {
  static key(node) {
    const json=node.toJSON();
    const normalize=n=>{if(n.attrs)delete n.attrs.dir;n.content?.forEach(normalize)};
    normalize(json);return JSON.stringify(json);
  }
  constructor(editor,source,parse,html) {
    this.editor=editor;this.parse=parse;this.html=html;
    this.reset(source);
  }
  reset(source) {
    this.source=source;this.doc=this.editor.state.doc;this.cacheDoc=null;
    this.nodes=[];this.doc.forEach(n=>this.nodes.push(n));
    this.keys=this.nodes.map(window.SourceDocument.key);
    this.ranges=new Array(this.nodes.length);
    this.env={};
    const tokens=this.editor.storage.markdown.parser.md.parse(source,this.env);
    const offsets=[0];for(let i=0;i<source.length;i++)if(source[i]==='\n')offsets.push(i+1);
    const spans=[];let details=null,depth=0;
    for(const token of tokens) {
      if(token.level!==0||token.nesting<0||!token.map)continue;
      const start=offsets[token.map[0]]??source.length,end=offsets[token.map[1]]??source.length;
      if(token.type==='html_block') {
        const html=token.content.replace(/<!--[\s\S]*?-->/g,'');
        const tags=html.match(/<\/?details\b[^>]*>/gi)||[];
        if(tags.length) {
          if(details===null&&tags.some(t=>!/^<\//.test(t)))details=start;
          for(const tag of tags)depth+=/^<\//.test(tag)?-1:1;
          if(details!==null&&depth<=0){spans.push([details,end]);details=null;depth=0}
          if(details!==null||tags.length)continue;
        }
      }
      if(details===null)spans.push([start,end]);
    }
    if(details!==null)spans.push([details,source.length]);
    let cursor=0;
    for(let [start,end] of spans) {
      if(start===0&&source.charCodeAt(0)===0xfeff)start=1;
      const raw=source.slice(start,end);
      const parsed=this.parse(raw,this.env),children=[];parsed.forEach(n=>children.push(n));
      const keys=children.map(window.SourceDocument.key);
      if(keys.every((k,i)=>k===this.keys[cursor+i])) {
        const range={start,end,first:cursor,last:cursor+keys.length};
        for(let i=0;i<keys.length;i++)this.ranges[cursor+i]=range;
        cursor+=keys.length;
      }
      // Non-rendered comments and definitions remain in the untouched gaps.
    }
    if(source.trim()===''&&this.nodes.length===1)this.ranges[0]={start:0,end:source.length,first:0,last:1};
  }
  same(candidate,nodes) {
    try {
      const parsed=this.parse(candidate,this.env),keys=[];parsed.forEach(n=>keys.push(window.SourceDocument.key(n)));
      return JSON.stringify(keys)===JSON.stringify(nodes.map(window.SourceDocument.key));
    } catch {return false}
  }
  textPatch(raw,oldNodes,newNodes) {
    if(oldNodes.length!==newNodes.length)return null;
    const edits=[];
    function shape(a,b) {
      if(a.type!==b.type||JSON.stringify(a.attrs)!==JSON.stringify(b.attrs)||!a.sameMarkup(b)||a.childCount!==b.childCount)return false;
      if(a.isText){if(a.text!==b.text)edits.push([a.text,b.text]);return true}
      for(let i=0;i<a.childCount;i++)if(!shape(a.child(i),b.child(i)))return false;
      return true;
    }
    for(let i=0;i<oldNodes.length;i++)if(!shape(oldNodes[i],newNodes[i]))return null;
    if(edits.length!==1)return null;
    const [oldText,newText]=edits[0];
    // First try a literal text-leaf replacement, then the smallest changed
    // substring. Each candidate is parsed and checked against the desired model.
    const tryReplace=(old,added)=>{
      if(!old)return null;
      let from=0;
      for(let attempt=0;attempt<32;attempt++) {
        const at=raw.indexOf(old,from);if(at<0)break;from=at+1;
        const next=raw.slice(0,at)+added+raw.slice(at+old.length);
        if(this.same(next,newNodes))return next;
      }
      return null;
    };
    let result=tryReplace(oldText,newText);if(result!==null)return result;
    let p=0,s=0;while(p<oldText.length&&p<newText.length&&oldText[p]===newText[p])p++;
    while(s<oldText.length-p&&s<newText.length-p&&oldText.at(-1-s)===newText.at(-1-s))s++;
    const removed=oldText.slice(p,oldText.length-s),added=newText.slice(p,newText.length-s);
    result=tryReplace(removed,added);if(result!==null)return result;
    if(!removed) {
      for(let length=Math.min(48,p);length>0;length--) {
        const anchor=oldText.slice(p-length,p);let from=0;
        for(let attempt=0;attempt<16;attempt++) {
          const at=raw.indexOf(anchor,from);if(at<0)break;from=at+1;
          const next=raw.slice(0,at+anchor.length)+added+raw.slice(at+anchor.length);
          if(this.same(next,newNodes))return next;
        }
      }
    }
    return null;
  }
  restoreMetadata(candidate,raw) {
    // Preserve source details that the rich schema cannot express. Validation
    // below still checks the final fragment against the user's edited model.
    const tokens=this.editor.storage.markdown.parser.md.parse(raw,{...this.env});
    const unsupported=new Set(),titles=[];
    const supported=new Set('a b strong i em u s del strike code img br p div span mark details summary blockquote ul ol li h1 h2 h3 h4 h5 h6 table thead tbody tr td th pre hr'.split(' '));
    const visit=token=>{
      if(token.type==='html_inline')for(const tag of token.content.matchAll(/<([a-z][\w-]*)\b/gi))if(!supported.has(tag[1].toLowerCase()))unsupported.add(tag[1]);
      if(token.type==='link_open'&&token.attrGet('title'))titles.push([token.attrGet('href'),token.attrGet('title')]);
      token.children?.forEach(visit);
    };tokens.forEach(visit);
    for(const tag of unsupported) {
      const pattern=new RegExp('<'+tag+'\\b[^>]*>([^<]+)</'+tag+'>','gi');
      for(const match of raw.matchAll(pattern)) {
        const element=document.createElement('div');element.innerHTML=match[1];const text=element.textContent;
        if(text&&!candidate.includes(match[0])&&candidate.split(text).length===2)candidate=candidate.replace(text,match[0]);
      }
    }
    for(const [href,title] of titles) {
      const escaped=title.replace(/"/g,'\\"');
      candidate=candidate.replace(']('+href+')',']('+href+' "'+escaped+'")');
    }
    // Keep alignment markers while allowing an intentional column resize to
    // change the dash counts. Alignment is not represented by this editor UI.
    const delimiter=line=>line.trim().replace(/^\|/,'').replace(/\|$/,'').split('|').map(c=>c.trim());
    const rows=raw.split(/\r?\n/).map(delimiter),alignment=rows.find(c=>c.length>1&&c.every(v=>/^:?-{3,}:?$/.test(v)));
    if(alignment)candidate=candidate.split('\n').map(line=>{
      const cells=delimiter(line);
      if(cells.length!==alignment.length||!cells.every(v=>/^:?-{3,}:?$/.test(v)))return line;
      return '| '+cells.map((cell,i)=>(alignment[i].startsWith(':')?':':'')+cell.replace(/:/g,'')+(alignment[i].endsWith(':')?':':'')).join(' | ')+' |';
    }).join('\n');
    return candidate;
  }
  serializeNodes(nodes,raw) {
    const serializer=this.editor.storage.markdown.serializer;
    const doc=this.editor.schema.topNodeType;
    // Separate block atoms (notably images) and adjacent lists explicitly.
    const parts=nodes.map(n=>serializer.serialize(doc.create(null,[n])));
    let candidate=this.restoreMetadata(parts.join('\n\n'),raw);
    if(this.same(candidate,nodes))return candidate;
    candidate=this.restoreMetadata(nodes.map(n=>this.html(n)).join('\n\n'),raw);
    if(this.same(candidate,nodes))return candidate;
    throw new Error('This block cannot be saved faithfully in Preview. Your edits are kept in the editor; use Code to preserve its source.');
  }
  serialize() {
    const current=this.editor.state.doc;
    if(current===this.cacheDoc)return this.cache;
    const nodes=[];current.forEach(n=>nodes.push(n));
    const keys=nodes.map(window.SourceDocument.key);
    // Immutable ProseMirror identities distinguish repeated identical blocks.
    // A semantic-only diff could otherwise delete the wrong source spelling.
    const identities=new Map(this.nodes.map((n,i)=>[n,i])),used=new Set();
    const matches=nodes.map(n=>{const i=identities.get(n);if(i!==undefined)used.add(i);return i});
    const candidates=new Map();this.keys.forEach((key,i)=>{if(!candidates.has(key))candidates.set(key,[]);candidates.get(key).push(i)});
    const cursors=new Map();
    matches.forEach((match,index)=>{
      if(match!==undefined)return;
      const list=candidates.get(keys[index])||[];let cursor=cursors.get(keys[index])||0;
      while(cursor<list.length&&used.has(list[cursor]))cursor++;
      if(cursor<list.length){matches[index]=list[cursor];used.add(list[cursor]);cursor++}
      cursors.set(keys[index],cursor);
    });
    const original=this.nodes.map((_,i)=>'original:'+i),currentKeys=matches.map((m,i)=>m===undefined?'new:'+i:'original:'+m);
    const ops=comparisonDiff(original,currentKeys),hunks=[];let a=0,b=0;
    for(let i=0;i<ops.length;i++) {
      const op=ops[i];if(op.type==='equal'){a+=op.values.length;b+=op.values.length;continue}
      const h={a,b,endA:a,endB:b};
      while(i<ops.length&&ops[i].type!=='equal'){
        if(ops[i].type==='delete')a+=ops[i].values.length;else b+=ops[i].values.length;i++;
      }
      i--;h.endA=a;h.endB=b;
      // A Markdown fragment can render as multiple editor nodes. Keep that
      // source fragment indivisible when a child is edited or inserted.
      const left=this.ranges[h.a],right=this.ranges[h.endA-1];
      if(h.endA>h.a) {
        if(!left||!right)throw new Error('This edited block has no reliable Markdown source range. Your edits are preserved; switch to Code before saving.');
        h.b-=h.a-left.first;h.a=left.first;
        h.endB+=right.last-h.endA;h.endA=right.last;
      } else if(left&&h.a>left.first) {
        h.b-=h.a-left.first;h.endB+=left.last-h.a;h.a=left.first;h.endA=left.last;
      }
      const previous=hunks.at(-1);
      if(previous&&h.a<previous.endA){previous.endA=Math.max(previous.endA,h.endA);previous.endB=Math.max(previous.endB,h.endB)}else hunks.push(h);
    }
    let output='',position=0;
    for(const h of hunks) {
      const start=this.ranges[h.a]?.start??this.ranges.at(-1)?.end??this.source.length;
      const end=h.endA>h.a?this.ranges[h.endA-1].end:start;
      const raw=this.source.slice(start,end),selected=nodes.slice(h.b,h.endB);
      let replacement=selected.length?this.textPatch(raw,this.nodes.slice(h.a,h.endA),selected):'';
      if(replacement===null) {
        replacement=this.serializeNodes(selected,raw);
        const eol=this.source.includes('\r\n')?'\r\n':'\n';
        replacement=replacement.replace(/\r?\n/g,eol);
        if(h.a===h.endA) {
          if(start>0&&!this.source.slice(0,start).endsWith(eol+eol))replacement=eol+replacement;
          replacement+=eol+eol;
        } else replacement+=(raw.match(/(?:\r?\n)+$/)||[''])[0];
      }
      output+=this.source.slice(position,start)+replacement;position=end;
    }
    output+=this.source.slice(position);
    // Structural edits can make adjacent blocks merge. Reject a lossy result
    // instead of silently changing document structure or dropping unknown text.
    if(hunks.some(h=>h.endA-h.a!==h.endB-h.b)&&!this.same(output,nodes))throw new Error('These blocks cannot be combined faithfully in Markdown. Your edits are preserved in the editor.');
    this.cacheDoc=current;this.cache=output;return output;
  }
};
