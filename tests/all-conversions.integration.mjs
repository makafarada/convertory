import {readFile,writeFile} from 'node:fs/promises';
const root='tmp/conversion-tests/';
const cases=[
 ['Image to PDF',['invoice.png']], ['PDF to Excel',['table.pdf']],
 ['PDF to PowerPoint',['table.pdf']], ['PDF to Text',['table.pdf']],
 ['Merge PDF',['table.pdf','second.pdf']],
 ['Compress PDF',['table.pdf']], ['Watermark PDF',['table.pdf'],{watermark:'ÖZEL TEST'}],
 ['More Formats',['table.pdf'],{format:'png'}], ['More Formats',['table.pdf'],{format:'txt'}],
 ['Image to Text',['invoice.png']], ['Image to Excel',['invoice.png']],
 ['Word to PDF',['document.docx']], ['Excel to PDF',['workbook.xlsx']],
 ['PowerPoint to PDF',['slides.pptx']]
];
const results=[];
for(const [index,[tool,names,options]] of cases.entries()) {
 try {
  const files=await Promise.all(names.map(async name=>({name,data:(await readFile(root+name)).toString('base64')})));
  const response=await fetch('http://127.0.0.1:4755/api/convert',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({tool,files,options}),signal:AbortSignal.timeout(190000)});
  const result=await response.json();
  if(!response.ok) throw new Error(result.error);
  const download=await fetch(new URL(result.downloadUrl,'http://127.0.0.1:4755'));
  if(!download.ok) throw new Error('Download failed');
  const bytes=Buffer.from(await download.arrayBuffer());
  const file=`result-${index}${result.outputName.slice(result.outputName.lastIndexOf('.'))}`;
  await writeFile(root+file,bytes);
  results.push({tool,passed:true,file,bytes:bytes.length,note:result.note});
 } catch(error) {results.push({tool,passed:false,error:error.message});}
 console.log(JSON.stringify(results.at(-1)));
}
await writeFile(root+'results.json',JSON.stringify(results,null,2));
if(results.some(r=>!r.passed))process.exitCode=1;
