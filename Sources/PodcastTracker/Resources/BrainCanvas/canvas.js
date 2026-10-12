(() => {
'use strict';
const svg=d3.select('svg'), viewport=d3.select('#viewport'), linkLayer=d3.select('#links'), nodeLayer=d3.select('#nodes');
const colors={Episode:'#8b7ee8',Summary:'#a88af4',Transcript:'#44b9a9',Chat:'#e6ad63'};
let data={nodes:[],links:[]}, nodes=[], links=[], simulation, selected=null, hovered=null, transform=d3.zoomIdentity, showLabels=true, showTopics=false;
let width=1,height=1, first=true, disposed=false, signature='', reduce=false, pinned=new Map(), activeKinds=new Set(['Episode','Summary','Transcript','Chat']);
try{const saved=JSON.parse(sessionStorage.getItem('brainCanvasPins')||'[]');pinned=new Map(saved);}catch{}
function savePins(){try{sessionStorage.setItem('brainCanvasPins',JSON.stringify([...pinned]));}catch{}}
const media=window.matchMedia('(prefers-reduced-motion: reduce)');
function host(id){const payload={id};if(window.webkit?.messageHandlers?.brainCanvas)window.webkit.messageHandlers.brainCanvas.postMessage(payload);else if(window.BrainCanvasNative)window.BrainCanvasNative.selectNode(id);}
const zoom=d3.zoom().scaleExtent([.2,4]).filter(e=>!e.target.closest?.('.node')&&(!e.ctrlKey||e.type==='wheel')&&!e.button).on('zoom',e=>{transform=e.transform;viewport.attr('transform',transform);updateLabels()});
svg.call(zoom).on('dblclick.zoom',null).on('click',e=>{if(e.target===svg.node()){select(null);}});
function animation(selection){return reduce?selection:selection.transition().duration(240).ease(d3.easeCubicOut);}
function fit(){if(!nodes.length)return;const xs=d3.extent(nodes,n=>n.x),ys=d3.extent(nodes,n=>n.y);const k=Math.min(1.25,(width-100)/Math.max(150,xs[1]-xs[0]+120),(height-150)/Math.max(150,ys[1]-ys[0]+110));const t=d3.zoomIdentity.translate(width/2,height/2+8).scale(Math.max(.2,k)).translate(-(xs[0]+xs[1])/2,-(ys[0]+ys[1])/2);animation(svg).call(zoom.transform,t);}
function neighborIds(id){const set=new Set([id]);links.forEach(l=>{if(l.source.id===id)set.add(l.target.id);if(l.target.id===id)set.add(l.source.id)});return set;}
function emphasize(){const focus=hovered||selected,near=focus?neighborIds(focus):null;nodeLayer.selectAll('.node').classed('selected',n=>n.id===selected).attr('opacity',n=>near&&!near.has(n.id)?.18:1);linkLayer.selectAll('.edge').classed('focused',l=>focus&&(l.source.id===focus||l.target.id===focus)).attr('opacity',l=>{const hit=focus&&(l.source.id===focus||l.target.id===focus);return l.type==='topic'?(hit?1:showTopics?.55:0):(focus?(hit?1:.13):.6)});updateLabels();}
function select(id,notify=true){selected=id;emphasize();const node=nodes.find(n=>n.id===id);document.getElementById('announce').textContent=node?`${node.title}. ${node.kind}. ${neighborIds(id).size-1} connected documents.`:'Selection cleared';if(notify&&node)host(node.sourceID);}
function updateLabels(){nodeLayer.selectAll('.hit').attr('r',22/transform.k);nodeLayer.selectAll('text').attr('opacity',n=>showLabels&&(transform.k>.55||n.kind==='Episode'||n.id===selected||n.id===hovered)?1:0);}
function render(){if(disposed)return;linkLayer.selectAll('.edge').attr('x1',l=>l.source.x).attr('y1',l=>l.source.y).attr('x2',l=>l.target.x).attr('y2',l=>l.target.y);nodeLayer.selectAll('.node').attr('transform',n=>`translate(${n.x},${n.y})`);}
function reheat(){if(reduce){simulation.stop();simulation.alpha(.2).tick(80);render()}else simulation.alpha(.18).restart();}
function build(){
 if(disposed)return;simulation?.stop();const previous=new Map(nodes.map(n=>[n.id,n]));
 nodes=data.nodes.filter(n=>activeKinds.has(n.kind)).map(n=>{const old=previous.get(n.id),pin=pinned.get(n.id);return {...n,x:pin?.x??old?.x,y:pin?.y??old?.y,fx:pin?.x,fy:pin?.y}});
 const ids=new Set(nodes.map(n=>n.id));links=data.links.filter(l=>ids.has(l.source)&&ids.has(l.target)).map(l=>({...l}));
 document.getElementById('empty').style.display=nodes.length?'none':'block';
 linkLayer.selectAll('line').data(links,l=>l.source+'|'+l.target).join('line').attr('class',l=>'edge '+l.type);
 const group=nodeLayer.selectAll('g').data(nodes,n=>n.id).join(enter=>{const g=enter.append('g').attr('class',n=>'node '+(n.kind==='Episode'?'episode':'')).attr('role','button').attr('tabindex',0);
 g.append('circle').attr('class','hit').attr('r',22).attr('fill','transparent');g.append('circle').attr('class','halo');g.append('circle').attr('class','dot');g.append('text');return g;});
 group.attr('aria-label',n=>`${n.title}, ${n.kind}. Enter to inspect; arrow keys to move; Escape to clear.`).attr('data-node-id',n=>n.id);
 group.select('.halo').attr('r',n=>n.kind==='Episode'?18:13);group.select('.dot').attr('r',n=>n.kind==='Episode'?10:6).attr('fill',n=>colors[n.kind]||colors.Episode);
 group.select('text').attr('y',n=>n.kind==='Episode'?31:24).text(n=>n.title.length>32?n.title.slice(0,31)+'…':n.title);
 group.on('click',(e,n)=>{e.stopPropagation();select(n.id)}).on('dblclick',(e,n)=>{e.stopPropagation();const t=d3.zoomIdentity.translate(width/2,height/2).scale(1.7).translate(-n.x,-n.y);animation(svg).call(zoom.transform,t)}).on('mouseenter',(e,n)=>{if(matchMedia('(hover:hover)').matches){hovered=n.id;emphasize()}}).on('mouseleave',()=>{hovered=null;emphasize()}).on('keydown',(e,n)=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();select(n.id)}else if(e.key==='Escape'){select(null)}else if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();n.fx=(n.fx??n.x)+(e.key==='ArrowLeft'?-15:e.key==='ArrowRight'?15:0);n.fy=(n.fy??n.y)+(e.key==='ArrowUp'?-15:e.key==='ArrowDown'?15:0);pinned.set(n.id,{x:n.fx,y:n.fy});savePins();reheat();}});
 group.call(d3.drag().container(()=>viewport.node()).subject((e,n)=>n).on('start',(e,n)=>{if(!reduce&&!e.active)simulation.alphaTarget(.12).restart();n.fx=n.x;n.fy=n.y;}).on('drag',(e,n)=>{n.fx=e.x;n.fy=e.y;n.x=e.x;n.y=e.y;render();}).on('end',(e,n)=>{if(!e.active)simulation.alphaTarget(0);pinned.set(n.id,{x:n.fx,y:n.fy});savePins();if(!e.sourceEvent.defaultPrevented)select(n.id);}));
 simulation=d3.forceSimulation(nodes).force('link',d3.forceLink(links).id(n=>n.id).distance(l=>l.type==='document'?72:185).strength(l=>l.type==='document'?.85:.035)).force('charge',d3.forceManyBody().strength(n=>n.kind==='Episode'?-650:-180)).force('collide',d3.forceCollide(n=>n.kind==='Episode'?66:38).iterations(2)).force('x',d3.forceX(0).strength(.018)).force('y',d3.forceY(0).strength(.023)).alphaDecay(.045).velocityDecay(.5).on('tick',render);
 // Settle the layout before fitting. Motion then gently relaxes real forces, rather than orbiting reading content.
 simulation.stop().tick(100);render();emphasize();if(first&&nodes.length){fit();first=false}if(!reduce)simulation.alpha(.18).restart();
}
function setData(payload){reduce=!!payload.reduceMotion||media.matches;document.documentElement.classList.toggle('dark',!!payload.dark);const next=JSON.stringify([payload.nodes,payload.links]);if(signature===next){emphasize();return}signature=next;data={nodes:payload.nodes||[],links:payload.links||[]};build();}
new ResizeObserver(()=>{const oldWidth=width,oldHeight=height;width=svg.node().clientWidth;height=svg.node().clientHeight;if(nodes.length&&(first||Math.abs(oldWidth-width)>60||Math.abs(oldHeight-height)>60))fit();}).observe(document.getElementById('space'));
document.getElementById('zoomIn').onclick=()=>animation(svg).call(zoom.scaleBy,1.25);document.getElementById('zoomOut').onclick=()=>animation(svg).call(zoom.scaleBy,.8);document.getElementById('fit').onclick=()=>fit();
document.getElementById('relayout').onclick=()=>{pinned.clear();savePins();nodes.forEach(n=>{n.fx=null;n.fy=null});simulation.alpha(.65);if(reduce){simulation.stop().tick(160);render();fit()}else{simulation.restart();setTimeout(fit,250)}};
document.getElementById('labels').onclick=e=>{showLabels=!showLabels;e.currentTarget.setAttribute('aria-pressed',showLabels);updateLabels()};document.getElementById('connections').onclick=e=>{showTopics=!showTopics;e.currentTarget.setAttribute('aria-pressed',showTopics);emphasize()};
const legend=document.querySelector('.legend');['Episode','Summary','Transcript','Chat'].forEach(kind=>{const button=document.createElement('button');button.setAttribute('aria-pressed','true');button.setAttribute('aria-label','Show '+kind.toLowerCase()+' nodes');const dot=document.createElement('span');dot.className='swatch';dot.style.background=colors[kind];button.append(dot,document.createTextNode(kind==='Episode'?'Episodes':kind));button.onclick=()=>{activeKinds.has(kind)?activeKinds.delete(kind):activeKinds.add(kind);button.setAttribute('aria-pressed',activeKinds.has(kind));build()};legend.append(button)});
if(matchMedia('(pointer:coarse)').matches)document.getElementById('hint').textContent='Drag nodes · pinch to explore';
media.addEventListener?.('change',()=>{reduce=media.matches;if(reduce){simulation?.stop();render()}});
window.brainGraph={setData,fit,select,dispose(){disposed=true;simulation?.stop();svg.interrupt()},debug(){return {nodes:nodes.length,links:links.length,selected,zoom:transform.k,pinned:pinned.size,running:simulation?.alpha()>.02}}};
width=svg.node().clientWidth;height=svg.node().clientHeight;
})();
