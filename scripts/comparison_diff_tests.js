const assert=require('node:assert/strict');
const diff=require('../Resources/Webview/comparison-diff.js');
function check(a,b){const ops=diff(a,b);assert.deepEqual(ops.filter(x=>x.type!=='add').flatMap(x=>x.values),a);assert.deepEqual(ops.filter(x=>x.type!=='delete').flatMap(x=>x.values),b)}
for(const [a,b] of [[[],[]],[[],['x']],[['x'],[]],[['a','b'],['a','x','b']],[['a','a','b'],['a','b','a']],[['😀','é','中'],['中','😀']]])check(a,b);
let seed=42;const random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed};
for(let i=0;i<400;i++)check(Array.from({length:random()%80},()=>String(random()%12)),Array.from({length:random()%80},()=>String(random()%12)));
const large=Array.from({length:50000},(_,i)=>`line ${i}`),changed=large.slice();changed.splice(25000,3,'external addition');check(large,changed);
check(Array(20000).fill('repeated'),Array(18000).fill('different'));
console.log('PASS: comparison reconstruction, Unicode, randomized edits, 50,000 lines, repeated lines (bounded memory)');
