#!/usr/bin/env python3
"""Offline process/protocol tests. Fake JDT implements framing, callbacks and hangs."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def mock_server():
    r, w = sys.stdin.buffer, sys.stdout.buffer
    def send(v):
        body=json.dumps(v).encode()
        w.write(f'Content-Length: {len(body)}\r\n\r\n'.encode()+body)
        w.flush()
    pending_text = None
    current_text = None
    while True:
        headers={}
        while True:
            line=r.readline()
            if not line:return
            if line==b'\r\n':break
            k,v=line.decode().split(':',1);headers[k.lower()]=v.strip()
        msg=json.loads(r.read(int(headers['content-length'])))
        method=msg.get('method')
        if method=='exit':return
        if method=='initialize':
            send({'jsonrpc':'2.0','id':msg['id'],'result':{'capabilities':{'positionEncoding':'utf-16'},'serverInfo':{'name':'fake','version':'1.60.0'}}})
        elif method=='initialized':
            send({'jsonrpc':'2.0','id':'configuration','method':'workspace/configuration','params':{'items':[{'section':'java'}]}})
        elif msg.get('id')=='configuration':
            assert msg['result'][0]['autobuild']['enabled']
            send({'jsonrpc':'2.0','method':'language/status','params':{'type':'Started','message':'Ready'}})
        elif method in ('textDocument/didOpen', 'textDocument/didChange'):
            if method.endswith('didOpen'):
                pending_text = msg['params']['textDocument']['text']
            else:
                pending_text = msg['params']['contentChanges'][0]['text']
        elif method=='textDocument/documentSymbol':
            # Lifecycle work is asynchronous in JDT. Only a method that joins
            # those jobs establishes that the next extension sees the new text.
            current_text = pending_text
            send({'jsonrpc':'2.0','id':msg['id'],'result':[]})
        elif method=='java/getMoveDestinations':
            if current_text != pending_text:
                send({'jsonrpc':'2.0','id':msg['id'],'result':{'errorMessage':'stale document'}})
            else:
                send({'jsonrpc':'2.0','id':msg['id'],'result':{'destinations':[{'text':current_text}]}})
        elif method=='workspace/symbol':
            if msg['params']['query']=='hang':continue
            if msg['params']['query']=='crash':return
            send({'jsonrpc':'2.0','method':'language/status','params':{'type':'ServiceReady'}})
            # A late response for a timed-out request must not consume this result.
            send({'jsonrpc':'2.0','id':987654,'result':'late'})
            send({'jsonrpc':'2.0','id':msg['id'],'result':[{'name':'One'},{'name':'Two'}]})
        elif method=='shutdown':send({'jsonrpc':'2.0','id':msg['id'],'result':None})
        elif method and 'id' in msg:send({'jsonrpc':'2.0','id':msg['id'],'error':{'code':-32601,'message':'unsupported fake request'}})


def main():
    binary=Path(__file__).resolve().parents[1]/'target/debug/java-lsp'
    with tempfile.TemporaryDirectory(prefix='java-lsp-protocol-') as tmp:
        base=Path(tmp);root=base/'root';root.mkdir()
        launcher=base/'jdtls'
        launcher.write_text('#!/bin/sh\nexec '+sys.executable+' '+str(Path(__file__).resolve())+' --mock\n')
        launcher.chmod(0o755)
        env=os.environ|{'JAVA_LSP_JDTLS':str(launcher),'XDG_RUNTIME_DIR':str(base/'run'),'XDG_STATE_HOME':str(base/'state'),'XDG_CACHE_HOME':str(base/'cache')}
        def call(*args):
            p=subprocess.run([str(binary),'--root',str(root),*args],env=env,capture_output=True,text=True,timeout=20)
            assert p.stdout,(p.returncode,p.stderr)
            return json.loads(p.stdout)
        assert call('status')['result']['running'] is False
        assert not (base/'run').exists(), 'status started daemon or created state'
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
                results=list(pool.map(lambda _:call('start'),range(4)))
            assert all(v['ok'] for v in results),results
            pid=call('status')['result']['pid']
            value=call('symbols','--query','x','--limit','1')['result']
            assert value=={'items':[{'name':'One'}],'total':2,'truncated':True},value
            timeout=call('symbols','--query','hang','--timeout','1')
            assert timeout['error']['code']=='timeout',timeout
            assert call('symbols','--query','x')['ok']
            assert call('status')['result']['pid']==pid
            source=root/'Example.java'
            for text in ['class Before {}', 'class After {}']:
                source.write_text(text)
                result=call('refactor','move','--file','Example.java','--describe')
                assert result['ok'] and result['result']['destinations'][0]['text']==text,result
            assert call('symbols','--query','crash')['error']['code']=='disconnected'
            assert call('restart')['ok']
            assert call('status')['result']['pid']!=pid
            assert call('symbols','--query','x')['ok']
            assert call('stop')['ok']
            time.sleep(.3)
            assert not call('status')['result']['running']
        finally:
            call('stop')
    print('PASS offline protocol: concurrent startup, callbacks, bounds, cancellation, crash, restart')

if __name__=='__main__':
    if '--mock' in sys.argv:mock_server()
    else:main()
