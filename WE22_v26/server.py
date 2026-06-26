# FRONTLINE 2022 — server.py v3.6
#!/usr/bin/env python3
"""FRONTLINE 2022 - Serveur HTTP+WebSocket avec système de ROOMS v1.3"""
import asyncio, json, logging, os, random
from aiohttp import web, WSMsgType

logging.basicConfig(level=logging.INFO, format='%(asctime)s  %(message)s', datefmt='%H:%M:%S')
log = logging.getLogger('FL22')

# ─── Rooms ────────────────────────────────────────────────────────────────────
rooms = {}  # code → {'clients': {pid: ws}, 'states': {pid: state}}

def gen_code():
    chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    while True:
        code = ''.join(random.choices(chars, k=6))
        if code not in rooms:
            return code

async def room_broadcast(code, msg, exclude=None):
    if code not in rooms: return
    data = json.dumps(msg)
    for pid, ows in list(rooms[code]['clients'].items()):
        if pid == exclude: continue
        try: await ows.send_str(data)
        except: pass

# ─── WebSocket ────────────────────────────────────────────────────────────────
async def ws_handler(request):
    ws = web.WebSocketResponse(heartbeat=25)
    await ws.prepare(request)
    pid = id(ws)
    room_code = None
    log.info(f'+ Connexion {pid}')

    try:
        await ws.send_str(json.dumps({'type': 'connected', 'id': pid}))

        async for msg in ws:
            if msg.type != WSMsgType.TEXT: continue
            try: d = json.loads(msg.data)
            except: continue
            t = d.get('type')

            # ── Créer une room ──────────────────────────────────────────────
            if t == 'create_room':
                # Quitter ancienne room si nécessaire
                if room_code and room_code in rooms:
                    rooms[room_code]['clients'].pop(pid, None)
                    rooms[room_code]['states'].pop(pid, None)
                    if not rooms[room_code]['clients']:
                        del rooms[room_code]
                code = gen_code()
                rooms[code] = {
                    'clients': {pid: ws},
                    'states': {pid: {'id':pid,'x':0,'y':0,'z':0,'yaw':0,'sfk':'UA_REG','health':100}}
                }
                room_code = code
                log.info(f'  Room créée: {code} (joueur {pid})')
                await ws.send_str(json.dumps({'type':'room_created','code':code,'id':pid}))

            # ── Rejoindre une room ──────────────────────────────────────────
            elif t == 'join_room':
                code = d.get('code','').upper().strip()
                if code not in rooms:
                    await ws.send_str(json.dumps({'type':'room_error','msg':f'Code "{code}" introuvable'}))
                    continue
                # Quitter ancienne room
                if room_code and room_code in rooms:
                    rooms[room_code]['clients'].pop(pid, None)
                    rooms[room_code]['states'].pop(pid, None)
                    if not rooms[room_code]['clients']:
                        del rooms[room_code]
                rooms[code]['clients'][pid] = ws
                rooms[code]['states'][pid] = {'id':pid,'x':0,'y':0,'z':0,'yaw':0,'sfk':'UA_REG','health':100}
                room_code = code
                n = len(rooms[code]['clients'])
                log.info(f'  Room {code}: joueur {pid} rejoint ({n} joueurs)')
                await ws.send_str(json.dumps({'type':'room_joined','code':code,'id':pid,'players':n}))
                # Envoyer les positions existantes au nouveau joueur
                existing = [s for pid2, s in rooms[code]['states'].items() if pid2 != pid]
                if existing:
                    await ws.send_str(json.dumps({'type':'players','players':existing}))
                # Prévenir les autres de l'arrivée
                for opid, ows in list(rooms[code]['clients'].items()):
                    if opid == pid: continue
                    try: await ows.send_str(json.dumps({'type':'players','players':[rooms[code]['states'][pid]]}))
                    except: pass

            # ── Position ────────────────────────────────────────────────────
            elif t == 'position' and room_code and room_code in rooms:
                room = rooms[room_code]
                if pid not in room['states']:
                    room['states'][pid] = {'id': pid}
                for k in ('x','y','z','yaw','sfk','health'):
                    if k in d: room['states'][pid][k] = d[k]
                room['states'][pid]['id'] = pid
                others = [s for s in room['states'].values() if s.get('id') != pid]
                # Broadcast uniquement aux membres de la room
                for opid, ows in list(room['clients'].items()):
                    if opid == pid: continue
                    try: await ows.send_str(json.dumps({'type':'players','players':others}))
                    except: pass

            # ── Tir ─────────────────────────────────────────────────────────
            elif t == 'shoot' and room_code and room_code in rooms:
                room = rooms[room_code]
                if pid not in room['states']: continue
                dx,dy,dz = d.get('dx',0),d.get('dy',0),d.get('dz',0)
                ln = (dx*dx+dy*dy+dz*dz)**.5 or 1
                dx,dy,dz = dx/ln,dy/ln,dz/ln
                sx = room['states'][pid].get('x',0)
                sy = room['states'][pid].get('y',0)+1.72
                sz = room['states'][pid].get('z',0)
                for opid, s in list(room['states'].items()):
                    if opid == pid: continue
                    ox,oy,oz = s.get('x',0),s.get('y',0)+1.0,s.get('z',0)
                    tx,ty,tz = ox-sx,oy-sy,oz-sz
                    dot = tx*dx+ty*dy+tz*dz
                    if dot < 0: continue
                    rx,ry,rz = tx-dot*dx,ty-dot*dy,tz-dot*dz
                    if rx*rx+ry*ry+rz*rz < 0.55 and opid in room['clients']:
                        try: await room['clients'][opid].send_str(json.dumps({'type':'hit','damage':30}))
                        except: pass

    except Exception as e:
        log.debug(f'WS err {pid}: {e}')
    finally:
        log.info(f'- Déconnexion {pid}')
        if room_code and room_code in rooms:
            rooms[room_code]['clients'].pop(pid, None)
            rooms[room_code]['states'].pop(pid, None)
            if not rooms[room_code]['clients']:
                del rooms[room_code]
                log.info(f'  Room {room_code} supprimée (vide)')
            else:
                await room_broadcast(room_code, {'type':'disconnect','id':pid})
        return ws

# ─── HTTP ─────────────────────────────────────────────────────────────────────
async def index_handler(request):
    try:
        with open('index.html','rb') as f:
            return web.Response(body=f.read(), content_type='text/html',
                headers={'Cache-Control':'no-cache'})
    except FileNotFoundError:
        return web.Response(text='index.html introuvable', status=404)

app = web.Application()
async def static_handler(request):
    name=request.match_info.get('file','')
    ext=name.rsplit('.',1)[-1] if '.' in name else ''
    mime={'glb':'model/gltf-binary','js':'application/javascript',
          'html':'text/html','png':'image/png'}.get(ext,'application/octet-stream')
    try:
        with open(name,'rb') as f:
            return web.Response(body=f.read(),content_type=mime,
                headers={'Cache-Control':'public,max-age=1800','Access-Control-Allow-Origin':'*'})
    except FileNotFoundError:
        return web.Response(text='not found: '+name,status=404)

app.router.add_get('/', index_handler)
app.router.add_get('/index.html', index_handler)
app.router.add_get('/ws', ws_handler)
app.router.add_get('/{file}', static_handler)

if __name__ == '__main__':
    PORT = int(os.environ.get('PORT', 8080))
    log.info('=' * 46)
    log.info('  FRONTLINE 2022  v1.3  ·  Rooms activées')
    log.info(f'  http://0.0.0.0:{PORT}   /ws')
    log.info('=' * 46)
    web.run_app(app, host='0.0.0.0', port=PORT, print=None, access_log=None)
