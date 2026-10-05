// CRINGE HERO · gerador de fases
// analisa o mp3 (BPM, bumbo, caixa, pratos e melodia) e escreve o chart em fases/<nome>.json
//
// uso:   node tools/gerar-fase.js "Artista - Música.mp3" [fácil|médio|difícil|insano]
// precisa do ffmpeg instalado. depois: jogo.html#admin → escolhe o mp3 → IMPORTAR JSON → TESTAR → PUBLICAR
var fs=require("fs"), path=require("path"), cp=require("child_process");
var SRC=process.argv[2], DIFF=(process.argv[3]||"difícil").toLowerCase();
if(!SRC){ console.log('uso: node tools/gerar-fase.js "Artista - Música.mp3" [fácil|médio|difícil|insano]'); process.exit(1); }
// densidade: fração dos tempos fortes e dos contratempos que viram nota
var PRESET={ "fácil":[0.45,0.03], "facil":[0.45,0.03], "médio":[0.6,0.1], "medio":[0.6,0.1], "difícil":[0.72,0.22], "dificil":[0.72,0.22], "insano":[0.85,0.45] }[DIFF];
if(!PRESET){ console.log("dificuldade inválida: "+DIFF); process.exit(1); }
var DIFF_NAME={facil:"fácil",medio:"médio",dificil:"difícil"}[DIFF]||DIFF;
// "Paramore - Misery Business (Lyrics).mp3" → artista + título limpos
var stem=path.basename(SRC).replace(/\.[^.]+$/,"").replace(/\s*[\(\[][^)\]]*(lyric|letra|official|oficial|video|v[íi]deo|audio|áudio|hd|hq)[^)\]]*[\)\]]/ig,"").trim();
var parts=stem.split(/\s+-\s+/), ARTIST=parts.length>1?parts[0].trim():"", TITLE=(parts.length>1?parts.slice(1).join(" - "):stem).trim();
var SLUG=TITLE.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"")||"fase";
var OUT=path.join(__dirname,"..","fases",SLUG+".json");

var SR=22050, N=1024, HOP=256, HT=HOP/SR;
var dec=cp.spawnSync("ffmpeg",["-v","error","-i",SRC,"-ac","1","-ar",String(SR),"-f","f32le","-"],{maxBuffer:1<<30});
if(dec.status!==0){ console.log("ffmpeg falhou:",String(dec.stderr||dec.error)); process.exit(1); }
var buf=dec.stdout; var x=new Float32Array(buf.buffer,buf.byteOffset,Math.floor(buf.length/4));
var nFr=Math.floor((x.length-N)/HOP);

// ---------- FFT radix-2 ----------
function fft(re,im){ var n=re.length;
  for(var i=1,j=0;i<n;i++){ var b=n>>1; for(;j&b;b>>=1) j^=b; j^=b; if(i<j){ var t=re[i];re[i]=re[j];re[j]=t; t=im[i];im[i]=im[j];im[j]=t; } }
  for(var len=2;len<=n;len<<=1){ var a=-2*Math.PI/len, wr=Math.cos(a), wi=Math.sin(a);
    for(var i2=0;i2<n;i2+=len){ var cr=1,ci=0; for(var k=0;k<len/2;k++){ var ur=re[i2+k],ui=im[i2+k],vr=re[i2+k+len/2]*cr-im[i2+k+len/2]*ci,vi=re[i2+k+len/2]*ci+im[i2+k+len/2]*cr;
      re[i2+k]=ur+vr; im[i2+k]=ui+vi; re[i2+k+len/2]=ur-vr; im[i2+k+len/2]=ui-vi; var t2=cr*wr-ci*wi; ci=cr*wi+ci*wr; cr=t2; } } } }
var win=new Float32Array(N); for(var i=0;i<N;i++) win[i]=0.5-0.5*Math.cos(2*Math.PI*i/N);
var BANDS=[[40,160],[160,2500],[5000,11000]];  // bumbo, caixa/guitarra/voz, pratos
var bin=function(f){ return Math.round(f*N/SR); };
var flux=BANDS.map(function(){ return new Float32Array(nFr); }), rms=new Float32Array(nFr), pitch=new Float32Array(nFr);
var prev=new Float32Array(N/2), re=new Float64Array(N), im=new Float64Array(N);
for(var f=0;f<nFr;f++){
  var o=f*HOP, e=0;
  for(var i=0;i<N;i++){ re[i]=x[o+i]*win[i]; im[i]=0; e+=x[o+i]*x[o+i]; }
  rms[f]=Math.sqrt(e/N); fft(re,im);
  var mag=new Float32Array(N/2); for(var k=1;k<N/2;k++) mag[k]=Math.log(1+100*Math.hypot(re[k],im[k]));
  BANDS.forEach(function(B,bi){ var s=0; for(var k=bin(B[0]);k<=bin(B[1]);k++){ var d=mag[k]-prev[k]; if(d>0) s+=d; } flux[bi][f]=s; });
  // "altura" da melodia: pico mais forte entre 200 e 1200 Hz
  var bk=0,bm=0; for(var k=bin(200);k<=bin(1200);k++) if(mag[k]>bm){ bm=mag[k]; bk=k; } pitch[f]=bk*SR/N;
  prev=mag;
}
function norm(a){ var s=a.slice().sort(); var p=s[Math.floor(s.length*0.98)]||1; return a.map(function(v){ return Math.min(1.5,v/p); }); }
flux=flux.map(norm);
var env=new Float32Array(nFr); for(var f2=0;f2<nFr;f2++) env[f2]=flux[0][f2]*1.0+flux[1][f2]*1.2+flux[2][f2]*0.6;

// ---------- BPM por autocorrelação + refino com pente ----------
function combScore(bpm,off){ var per=60/bpm, s=0, n=0; for(var t=off;t<nFr*HT;t+=per){ var fi=Math.round(t/HT); s+=Math.max(env[fi]||0,env[fi-1]||0,env[fi+1]||0); n++; } return s/n; }
var best={s:0};
for(var bpm=70;bpm<=210;bpm+=0.5){ for(var off=0;off<60/bpm;off+=0.005){ var s=combScore(bpm,off); if(s>best.s) best={s:s,bpm:bpm,off:off}; } }
for(var b2=best.bpm-0.6;b2<=best.bpm+0.6;b2+=0.02){ for(var off2=Math.max(0,best.off-0.03);off2<=best.off+0.03;off2+=0.001){ var s2=combScore(b2,off2); if(s2>best.s) best={s:s2,bpm:b2,off:off2}; } }
var BPM=Math.round(best.bpm*100)/100, PER=60/BPM;
// metade/dobro: escolhe a faixa jogável 120–200
if(BPM<110){ BPM*=2; PER/=2; }
console.log("bpm",BPM.toFixed(2),"offset",best.off.toFixed(3),"score",best.s.toFixed(3));

// ---------- notas ----------
function at(arr,t){ var fi=Math.round(t/HT), m=0; for(var d=-2;d<=2;d++) m=Math.max(m,arr[fi+d]||0); return m; }
function loud(t){ var fi=Math.round(t/HT), s=0, n=0; for(var d=-170;d<=170;d+=4){ var v=rms[fi+d]; if(v!=null){ s+=v; n++; } } return n?s/n:0; }
var maxLoud=0; for(var t0=0;t0<nFr*HT;t0+=1) maxLoud=Math.max(maxLoud,loud(t0));
var notes=[], lane=1, lastPitch=0, same=0, rep=1, firstBeat=null;
var totalBeats=Math.floor((nFr*HT-best.off)/PER);
var KEEP_Q=PRESET[0], KEEP_8=PRESET[1];
function slotStr(b){ var t=best.off+b/2*PER; return at(flux[0],t)*1.0+at(flux[1],t)*1.2+at(flux[2],t)*0.5; }
function pct(arr,q){ var s=arr.slice().sort(function(a,c){ return a-c; }); return s[Math.floor(s.length*q)]||0; }
var qs=[], es=[]; for(var bb=0;bb<totalBeats*2;bb++){ if(loud(best.off+bb/2*PER)/maxLoud<0.18) continue; (bb%2?es:qs).push(slotStr(bb)); }
var TH_Q=pct(qs,1-KEEP_Q), TH_8=pct(es,1-KEEP_8);
for(var b=0;b<totalBeats*2;b++){
  var beat=b/2, t=best.off+beat*PER, on8=b%2===1;
  var k=at(flux[0],t), sn=at(flux[1],t), hi=at(flux[2],t), str=k*1.0+sn*1.2+hi*0.5, lv=loud(t)/maxLoud;
  if(lv<0.18) continue;                              // trecho quase mudo
  if(str<(on8?TH_8:TH_Q)) continue;                  // contratempo só quando é forte
  if(firstBeat==null) firstBeat=beat;
  var p=pitch[Math.round(t/HT)];
  // contorno da melodia → sobe/desce de pista (como os charts do GH)
  var step = !lastPitch ? 0 : p>lastPitch*1.06 ? 1 : p<lastPitch/1.06 ? -1 : 0;
  if(step===0){ same++; if(same>=3){ step=lane>=2?-1:1; same=0; } } else same=0;
  var prevLane=lane;
  if(k>1.0 && sn<0.5) lane = lane<=1 ? lane : lane-1;  // bumbo seco puxa pra esquerda
  else if(hi>1.0 && sn>0.6 && step>=0) lane = Math.min(3,lane+1);  // prato/caixa forte puxa pra direita
  else lane=Math.max(0,Math.min(3,lane+step));
  // no máximo 3 notas seguidas na mesma pista
  rep = lane===prevLane ? rep+1 : 1;
  if(rep>3){ lane = lane>=2 ? lane-1 : lane+1; rep=1; }
  lastPitch=p;
  notes.push({ b:Math.round(beat*1000)/1000, l:lane });
  // acento forte (bumbo+prato) vira acorde de 2 notas
  if(!on8 && k>1.1 && hi>1.0 && notes.length>4 && notes[notes.length-2].b<beat-1){ notes.push({ b:Math.round(beat*1000)/1000, l:lane>=2?lane-2:lane+2 }); }
}
// notas longas: quando depois da nota vem um "buraco" de 2+ tempos sem ataque novo
// mas o som continua soando (acorde segurado, nota cantada longa), a nota vira de segurar
function avg(arr,t0,t1){ var a=Math.round(t0/HT), z=Math.round(t1/HT), s=0, n=0; for(var i=a;i<=z;i++){ if(arr[i]!=null){ s+=arr[i]; n++; } } return n?s/n:0; }
var cands=[];
for(var ni=0;ni<notes.length;ni++){
  var nb=notes[ni].b, nx=ni+1; while(nx<notes.length && notes[nx].b===nb) nx++;
  var gap=(nx<notes.length?notes[nx].b:nb+8)-nb;
  if(gap>=2){
    var ta=best.off+nb*PER, tz=best.off+(nb+gap)*PER;
    var sustain=avg(rms,ta+0.15,tz-0.15)/(avg(rms,ta,ta+0.1)||1), quiet=avg(env,ta+0.15,tz-0.15)/(TH_Q||1);
    var d=Math.min(8,Math.floor((gap-0.5)*2)/2);
    if(d>=1.5 && sustain>=0.5) cands.push({ i:ni, j:nx, d:d, score:sustain-quiet+Math.min(gap,6)*0.15 });
  }
  ni=nx-1;
}
// fica com as melhores: ~1 a cada 8s, sem duas coladas
var want=Math.round(nFr*HT/8), taken=[], holds=0;
cands.sort(function(a,b){ return b.score-a.score; }).forEach(function(c){
  if(holds>=want) return;
  var b0=notes[c.i].b; if(taken.some(function(t){ return Math.abs(t-b0)<6; })) return;
  for(var nj=c.i;nj<c.j;nj++) notes[nj].d=c.d;
  taken.push(b0); holds++;
});
// rebase: offset no primeiro tempo usado → b começa perto de 0
var base=Math.floor(firstBeat||0);
notes.forEach(function(n){ n.b=Math.round((n.b-base)*1000)/1000; });
var offsetMs=Math.round((best.off+base*PER)*1000);
var dur=nFr*HT, nps=notes.length/dur;
var lanes=[0,0,0,0]; notes.forEach(function(n){ lanes[n.l]++; });
console.log(TITLE+(ARTIST?" — "+ARTIST:"")+" · "+DIFF_NAME);
console.log("notas",notes.length,"(longas "+holds+")","n/s",nps.toFixed(2),"pistas",lanes.join("/"),"offset_ms",offsetMs);
fs.mkdirSync(path.dirname(OUT),{recursive:true});
fs.writeFileSync(OUT,JSON.stringify({ title:TITLE, artist:ARTIST, difficulty:DIFF_NAME, bpm:BPM, offset:offsetMs, notes:notes },null,1));
console.log("salvo em", path.relative(process.cwd(),OUT));
