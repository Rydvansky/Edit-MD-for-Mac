/* ProseMirror capabilities supplied by the licensed bundle. Decorations never
   change document content, serialization or undo history. */
window.NativeEditorIntegration = {
  install(api, tools) {
    const { Plugin, PluginKey, Decoration, DecorationSet } = tools;
    const key = new PluginKey('nativeComparison');
    const active = () => tools.isSource() ? tools.source() : tools.rich();
    function units(doc) {
      const result = [];
      doc.descendants((node,pos) => {
        if(!node.isTextblock && !node.isAtom) {
          // Include meaningful container attributes, e.g. a toggle title or a
          // checkbox state, without repeating all descendant text in the diff.
          if(['toggle','taskItem','callout'].includes(node.type.name)) {
            const attrs={...node.attrs};delete attrs.dir;
            result.push({key:JSON.stringify({type:node.type.name,attrs}),kind:node.type.name,
              text:node.attrs.summary??(node.attrs.checked===undefined?node.type.name:(node.attrs.checked?'[x]':'[ ]')),
              from:pos,to:pos+node.nodeSize,inline:false});
          }
          return true;
        }
        const json=node.toJSON();
        const normalize=n=>{if(n.attrs) delete n.attrs.dir;n.content?.forEach(normalize)};
        normalize(json);
        result.push({key:JSON.stringify(json),kind:node.type.name,
          text:node.isTextblock ? node.textBetween(0,node.content.size,'\n','\ufffc') : (node.attrs.alt||node.type.name),
          from:pos,to:pos+node.nodeSize,inline:node.isTextblock});
        return false;
      });
      return result;
    }
    function ensure(ed) {
      if(key.get(ed.state)) return;
      ed.registerPlugin(new Plugin({key,state:{init:()=>DecorationSet.empty,
        apply(tr,previous){return tr.getMeta(key)||previous.map(tr.mapping,tr.doc)}},
        props:{decorations:state=>key.getState(state)}}));
    }
    api.activeState=()=>{
      const json=active().state.doc.toJSON();
      const normalize=n=>{if(n.attrs)delete n.attrs.dir;n.content?.forEach(normalize)};
      normalize(json);
      return {mode:tools.isSource()?'source':'preview',signature:JSON.stringify(json)};
    };
    let cachedMarkdown=null,cachedUnits=null;
    const baseline=markdown=>{if(markdown!==cachedMarkdown){cachedUnits=units(tools.parse(markdown));cachedMarkdown=markdown}return cachedUnits};
    api.comparisonUnits=markdown=>tools.isSource()
      ? {mode:'source',base:markdown.split('\n'),current:tools.sourceMarkdown().split('\n')}
      : {mode:'preview',base:baseline(markdown),current:units(tools.rich().state.doc)};
    api.setComparisonDecorations=specs=>{
      const ed=active();ensure(ed);
      const decorations=[];
      for(const spec of specs) {
        const from=Math.min(Math.max(0,spec.from),ed.state.doc.content.size);
        const to=Math.min(Math.max(from,spec.to??from),ed.state.doc.content.size);
        if(spec.deleted) {
          const widget=document.createElement('del');widget.className='native-deleted';
          widget.textContent=spec.deleted;widget.contentEditable='false';
          decorations.push(Decoration.widget(from,widget,{side:-1,ignoreSelection:true}));
        }
        if(to>from) decorations.push(spec.node?Decoration.node(from,to,{class:'native-added-block'}):Decoration.inline(from,to,{class:'native-added'}));
      }
      ed.view.dispatch(ed.state.tr.setMeta(key,DecorationSet.create(ed.state.doc,decorations)).setMeta('addToHistory',false));
    };
    api.clearComparisonDecorations=()=>{
      for(const ed of [tools.rich(),tools.source()]) if(ed&&key.get(ed.state)) ed.view.dispatch(ed.state.tr.setMeta(key,DecorationSet.empty).setMeta('addToHistory',false));
    };
    api.replaceNativeContent=tools.replace;
  }
};
