#!/usr/bin/env python3
"""Real JDT LS acceptance tests; all writes use disposable projects and XDG roots."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

BINARY = Path(os.environ.get('JAVA_LSP_BIN', Path(__file__).resolve().parents[1] / 'target/debug/java-lsp'))
SOURCE = '''package demo;

public class Calculator {
    public int add(int a, int b) {
        int result = a + b;
        return result;
    }
    public int run() {
        return add(2, 3);
    }
}
'''

class Fixture:
    def __init__(self, base, name, gradle=False):
        self.root = base / name
        self.root.mkdir()
        self.env = os.environ | {k: str(base / d) for k, d in [('XDG_RUNTIME_DIR','run'), ('XDG_STATE_HOME','state'), ('XDG_CACHE_HOME','cache')]}
        self.file = Path('src/main/java/demo/Calculator.java')
        self.write(self.file, SOURCE)
        if gradle:
            self.write('settings.gradle', "rootProject.name = 'fixture'\n")
            self.write('build.gradle', "plugins { id 'java' }\njava { sourceCompatibility = JavaVersion.VERSION_21; targetCompatibility = JavaVersion.VERSION_21 }\n")
        else:
            self.write('pom.xml', '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>fixture</artifactId><version>1</version><properties><maven.compiler.release>21</maven.compiler.release></properties></project>')

    def write(self, path, text):
        path = self.root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def call(self, *args, spec=None, error=None):
        args = list(args)
        if spec is not None:
            args += ['--spec', '-']
        p = subprocess.run([str(BINARY), '--root', str(self.root)] + args, env=self.env, input=json.dumps(spec) if spec is not None else None, text=True, capture_output=True, timeout=700)
        try:
            out = json.loads(p.stdout)
        except ValueError:
            raise AssertionError((args, p.returncode, p.stdout, p.stderr))
        if error:
            assert not out['ok'] and out['error']['code'] == error, out
            return out
        assert p.returncode == 0 and out['ok'], (args, out, p.stderr)
        return out['result']

    def source(self):
        return {str(p.relative_to(self.root)): p.read_text() for p in self.root.rglob('*.java') if 'target' not in p.parts and 'build' not in p.parts}

    def preview(self, op, *args, spec=None):
        before = self.source()
        p = self.call('refactor', op, '--file', str(self.file), *args, spec=spec)
        assert self.source() == before, 'Preview changed project sources'
        assert not (self.root / '.project').exists(), 'JDT metadata leaked into source root'
        assert not (self.root / '.classpath').exists(), 'JDT metadata leaked into source root'
        return p

    def apply(self, plan):
        self.call('plan', 'apply', plan['plan_id'])
        self.compile()

    def compile(self):
        # Compile all modules together without downloading Maven/Gradle plugins.
        files = [str(p) for p in self.root.rglob('*.java') if 'target' not in p.parts and 'build' not in p.parts]
        p = subprocess.run(['javac', '-d', str(self.root / 'target/acceptance'), *files], capture_output=True, text=True)
        assert p.returncode == 0, p.stderr

    def reset(self):
        self.write(self.file, SOURCE)
        self.call('refresh')


def suite(f):
    t = time.monotonic()
    f.call('start')
    pid = f.call('status')['pid']
    assert f.call('symbols', '--query', 'Calculator')['items']
    assert f.call('status')['pid'] == pid
    print(f'PASS cold start and warm index ({time.monotonic()-t:.1f}s)', flush=True)
    p = f.preview('rename', '--at', '4:16', '--name', 'sum')
    assert '+    public int sum(' in p['diff'] and '+        return sum(' in p['diff']
    f.call('stop')
    time.sleep(1)
    assert f.call('plan', 'show', p['plan_id'])['diff'] == p['diff']
    f.apply(p)
    f.call('plan', 'apply', p['plan_id'], error='plan_state')
    f.reset()
    print('PASS rename, persistent preview, single application', flush=True)
    p = f.preview('rename', '--at', '4:16', '--name', 'sum')
    f.write(f.file, SOURCE + '\n')
    f.call('plan', 'apply', p['plan_id'], error='stale_plan')
    f.reset()
    print('PASS stale plan rejection', flush=True)
    for op, args in [('extract-method', ['--at','5:9','--end','6:23','--name','calculate']), ('extract-variable',['--at','5:22','--end','5:27','--name','total']), ('extract-constant',['--at','9:20','--end','9:21','--name','TWO'])]:
        p = f.preview(op, *args)
        f.apply(p)
        f.reset()
        print('PASS', op, flush=True)
    info = f.call('refactor','change-signature','--file',str(f.file),'--at','4:16','--describe')
    info['parameters'].reverse()
    p = f.preview('change-signature','--at','4:16',spec=info)
    assert 'add(3, 2)' in p['diff'], p
    f.apply(p)
    f.reset()
    print('PASS change signature and call-site update', flush=True)
    f.write(f.file, SOURCE.replace('package demo;', 'package demo;\nimport java.util.List;'))
    p = f.preview('imports')
    f.apply(p)
    f.reset()
    print('PASS organize imports', flush=True)
    info = f.call('refactor','extract-interface','--file',str(f.file),'--at','3:14','--describe')
    spec = {'name':'Adder','members':[info['members'][0]['handleIdentifier']],'destination':next(x for x in info['destinationResponse']['destinations'] if x['displayName']=='demo')}
    p = f.preview('extract-interface','--at','3:14',spec=spec)
    f.apply(p)
    (f.root/'src/main/java/demo/Adder.java').unlink()
    f.reset()
    print('PASS extract interface', flush=True)
    info = f.call('refactor','move','--file',str(f.file),'--describe')
    destination = next(x for x in info['destinations'] if x['isDefaultPackage'])
    p = f.preview('move',spec={'kind':'moveResource','destination':destination})
    f.apply(p)
    (f.root/'src/main/java/Calculator.java').unlink()
    f.reset()
    print('PASS move type', flush=True)
    p = f.preview('inline','--at','5:13')
    f.apply(p)
    f.reset()
    print('PASS inline variable', flush=True)
    # Undefined type has an import quick fix; wait for a fresh publication first.
    f.write(f.file, SOURCE.replace('int result = a + b;', 'int result = a + b;\n        List<String> names = null;'))
    d = f.call('diagnostics','--file',str(f.file),'--timeout','20')
    assert d['fresh'] and d['publication']['diagnostics'], d
    candidates = f.call('refactor','quickfix','--file',str(f.file),'--at','6:9','--describe')['items']
    chosen = next(a for a in candidates if "Import 'List' (java.util)" == a['title'])
    p = f.preview('quickfix','--at','6:9','--action',chosen['title'])
    f.apply(p)
    f.reset()
    print('PASS diagnostics and quick fix', flush=True)


def extended(f):
    # Inline method, nested type extraction, and static/instance member moves.
    p = f.preview('inline', '--at', '9:16')
    f.apply(p)
    f.reset()
    print('PASS inline method', flush=True)
    f.write(f.file, 'package demo;\npublic class Calculator {\n    public static class Nested { public int value() { return 1; } }\n}\n')
    p = f.preview('move', '--at', '3:25', spec={'kind':'moveTypeToNewFile'})
    f.apply(p)
    (f.root/'src/main/java/demo/Nested.java').unlink()
    f.reset()
    print('PASS nested type to file', flush=True)
    f.write('src/main/java/demo/Target.java', 'package demo;\npublic class Target { public int value = 2; }\n')
    f.write(f.file, 'package demo;\npublic class Calculator {\n    public static int value() { return 1; }\n    public int run() { return value(); }\n}\n')
    p = f.preview('move','--at','3:23',spec={'kind':'moveStaticMember','destination':'demo.Target'})
    f.apply(p)
    f.write('src/main/java/demo/Target.java', 'package demo;\npublic class Target { public int value = 2; }\n')
    f.write(f.file, 'package demo;\npublic class Calculator {\n    public int value(Target target) { return target.value; }\n}\n')
    info = f.call('refactor','move','--file',str(f.file),'--at','3:16','--describe',spec={'kind':'moveInstanceMethod'})
    p = f.preview('move','--at','3:16',spec={'kind':'moveInstanceMethod','destination':info['destinations'][0]})
    f.apply(p)
    (f.root/'src/main/java/demo/Target.java').unlink()
    f.reset()
    print('PASS static and instance member moves',flush=True)


def multimodule(base, fixtures):
    f=Fixture(base,'multi');fixtures.append(f)
    (f.root/f.file).unlink()
    f.write('pom.xml', '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>parent</artifactId><version>1</version><packaging>pom</packaging><modules><module>api</module><module>app</module></modules><properties><maven.compiler.release>21</maven.compiler.release></properties></project>')
    for name,dep in [('api',''),('app','<dependencies><dependency><groupId>demo</groupId><artifactId>api</artifactId><version>1</version></dependency></dependencies>')]:
        f.write(name+'/pom.xml','<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><parent><groupId>demo</groupId><artifactId>parent</artifactId><version>1</version></parent><artifactId>'+name+'</artifactId>'+dep+'</project>')
    f.file=Path('api/src/main/java/demo/Api.java')
    f.write(f.file, 'package demo;\npublic interface Api {\n    int compute(int x);\n    String compute(String x);\n}\n')
    f.write('app/src/main/java/demo/App.java','package demo;\npublic class App implements Api {\n    public int compute(int x) { return x + 1; }\n    public String compute(String x) { return x; }\n    public int run() { return compute(1); }\n}\n')
    f.call('start')
    refs=f.call('references','--file',str(f.file),'--at','3:9')
    assert refs['items'],refs
    p=f.preview('rename','--at','3:9','--name','calculate')
    assert len(p['files'])==2,p
    f.apply(p)
    assert 'String compute(String x)' in (f.root/f.file).read_text()
    assert 'return calculate(1)' in (f.root/'app/src/main/java/demo/App.java').read_text()
    print('PASS multi-module references, inheritance, overload isolation',flush=True)
    # Actual Git worktree discovery and independent daemons, not just two paths.
    for args in [['init','-q'],['add','.'],['-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture']]:
        subprocess.run(['git',*args],cwd=f.root,check=True,capture_output=True)
    worktree=base/'linked'
    subprocess.run(['git','worktree','add','-qb','fixture-linked',str(worktree)],cwd=f.root,check=True,capture_output=True)
    p=subprocess.run([str(BINARY),'start'],cwd=worktree,env=f.env,capture_output=True,text=True,timeout=700)
    assert json.loads(p.stdout)['ok'],p.stdout
    p=subprocess.run([str(BINARY),'status'],cwd=worktree,env=f.env,capture_output=True,text=True,check=True)
    assert json.loads(p.stdout)['result']['pid']!=f.call('status')['pid']
    subprocess.run([str(BINARY),'stop'],cwd=worktree,env=f.env,check=True,capture_output=True)
    print('PASS Git worktree discovery and process isolation',flush=True)


def main():
    base = Path(tempfile.mkdtemp(prefix='java-lsp-it-'))
    fixtures=[]
    try:
        f=Fixture(base,'maven');fixtures.append(f);suite(f);extended(f);multimodule(base,fixtures)
        other=Fixture(base,'other');fixtures.append(other)
        other.call('start')
        assert other.call('status')['pid'] != f.call('status')['pid']
        print('PASS independent workspace daemons',flush=True)
        if os.environ.get('JAVA_LSP_TEST_GRADLE') == '1':
            g=Fixture(base,'gradle',True);fixtures.append(g);suite(g)
        print('PASS integration suite',flush=True)
    except BaseException:
        print('Fixture retained for diagnosis:',base,flush=True)
        raise
    else:
        for f in fixtures:f.call('stop')
        time.sleep(1)
        shutil.rmtree(base)
    finally:
        for f in fixtures:
            try:f.call('stop')
            except Exception:pass

if __name__ == '__main__':main()
