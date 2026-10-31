const test=require('node:test');
const assert=require('node:assert/strict');
const core=require('../../Sources/LearningCore/Resources/Reader/glossary-core.js');
const document={kind:'note',path:'lessons/calculus.md',source:'# 微积分\n## 拉格朗日中值定理\n在闭区间连续。'};
function entry(id='calculus.mean-value',term='拉格朗日中值定理',aliases=['中值定理']){
 return {path:'术语/'+id+'.md',source:'# '+term+'\n\n```glossary\n'+JSON.stringify({id,term,aliases,subject:'微积分',related:[],notes:[{kind:'note',path:document.path,anchor:'拉格朗日中值定理'}]})+'\n```\n\n## 直觉\n平均速度也曾是瞬时速度。\n\n## 定义\n闭区间连续、开区间可导。\n\n## 例子\n$f(x)=x^2$ 在 $[0,2]$ 上，中值点为 $1$。'};
}
module.exports={entry,document};
test('catalog validates source and real note anchors',()=>{
 const result=core.build([entry()],[document]);
 assert.equal(result.terms.length,1);assert.equal(result.terms[0].notes[0].path,document.path);
 assert.ok(result.terms[0].body.includes('## 定义'));
 assert.throws(()=>core.build([entry()],[{...document,source:'# no heading'}]),/锚点/);
});
test('missing required sections, duplicate ids and unknown related ids fail',()=>{
 assert.throws(()=>core.build([entry(),entry()],[document]),/重复/);
 assert.throws(()=>core.build([{...entry(),source:entry().source.replace('## 定义','## 其他')}],[document]),/定义/);
 assert.throws(()=>core.build([{...entry(),source:entry().source.replace('"related":[]','"related":["missing"]')}],[document]),/关联/);
});
test('longest match wins and ambiguous aliases retain all senses',()=>{
 const library=core.build([entry(),entry('calculus.cauchy','柯西中值定理',['中值定理'])],[document]);
 const matcher=core.createMatcher(library);
 const matches=matcher.find('使用拉格朗日中值定理，或者中值定理。');
 assert.equal(matches.length,2);assert.equal(matches[0].text,'拉格朗日中值定理');
 assert.equal(matches[1].ids.length,2);
});
test('English boundaries and CJK matches use no whitespace assumption',()=>{
 const library=core.build([entry('linear.rank','矩阵的秩',['rank'])],[document]);
 const result=core.createMatcher(library).find('求矩阵的秩，rank 和 ranking 不同，RANK。');
 assert.deepEqual(result.map(x=>x.text),['矩阵的秩','rank','RANK']);
});
test('different courses have isolated dictionaries and empty library is normal',()=>{
 assert.equal(core.createMatcher(core.build([],[])).find('中值定理').length,0);
 const a=core.createMatcher(core.build([entry()],[document]));
 const b=core.createMatcher(core.build([entry('linear.rank','矩阵的秩',[])],[document]));
 assert.equal(a.find('中值定理').length,1);assert.equal(b.find('中值定理').length,0);
});
test('article title matches add real related notes without duplicate bindings',()=>{
 const result=core.build([entry()],[document]);
 assert.equal(result.terms[0].notes.length,1);
});
test('large vocabulary uses one multi-pattern matcher with Unicode-safe offsets',()=>{
 const terms=Array.from({length:10000},(_,n)=>({id:'t'+n,term:'数学词条'+n,aliases:[]}));
 const matcher=core.createMatcher({version:1,terms});
 const text='😀数学词条9999，数学词条100。';
 const result=matcher.find(text);
 assert.deepEqual(result.map(value=>value.text),['数学词条9999','数学词条100']);
 assert.equal(result[0].start,2);
});
