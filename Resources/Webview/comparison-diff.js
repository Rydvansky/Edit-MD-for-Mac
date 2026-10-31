/* Patience anchors plus bounded recursion: no quadratic LCS matrix. Repeated
   unanchored regions are shown as a replacement, never silently omitted. */
function comparisonDiff(base, other) {
  const out=[];
  function emit(type,start,end,values){
    if(end===start&&!values.length)return;
    const last=out[out.length-1];
    if(last&&last.type===type&&last.end===start){last.end=end;for(const value of values)last.values.push(value)}
    else out.push({type,start,end,values});
  }
  function visit(a,b,c,d,depth) {
    while(a<b&&c<d&&base[a]===other[c]){emit('equal',a,a+1,[other[c]]);a++;c++}
    let suffix=0;while(a<b-suffix&&c<d-suffix&&base[b-1-suffix]===other[d-1-suffix])suffix++;
    b-=suffix;d-=suffix;
    if(a===b)emit('add',a,b,other.slice(c,d));
    else if(c===d)emit('delete',a,b,base.slice(a,b));
    else {
      const left=new Map(),right=new Map();
      for(let i=a;i<b;i++)left.set(base[i],left.has(base[i])?-1:i);
      for(let i=c;i<d;i++)right.set(other[i],right.has(other[i])?-1:i);
      const pairs=[];for(let i=a;i<b;i++)if(left.get(base[i])===i&&right.get(base[i])>=0)pairs.push([i,right.get(base[i])]);
      const tails=[],indices=[],prev=new Array(pairs.length).fill(-1);
      pairs.forEach((p,i)=>{let lo=0,hi=tails.length;while(lo<hi){const m=(lo+hi)>>1;if(tails[m]<p[1])lo=m+1;else hi=m}if(lo)prev[i]=indices[lo-1];tails[lo]=p[1];indices[lo]=i});
      const anchors=[];let k=indices[tails.length-1];while(k!==undefined&&k>=0){anchors.push(pairs[k]);k=prev[k]}anchors.reverse();
      if(!anchors.length||depth>=24){emit('delete',a,b,base.slice(a,b));emit('add',b,b,other.slice(c,d))}
      else {let x=a,y=c;for(const [i,j] of anchors){visit(x,i,y,j,depth+1);emit('equal',i,i+1,[other[j]]);x=i+1;y=j+1}visit(x,b,y,d,depth+1)}
    }
    for(let i=0;i<suffix;i++)emit('equal',b+i,b+i+1,[other[d+i]]);
  }
  visit(0,base.length,0,other.length,0);return out;
}
if(typeof module!=='undefined')module.exports=comparisonDiff;
