#!/usr/bin/env python3
"""Optional offline integration probes; never part of a Make gate.

Run tools/test-integrate-dev.py. Every remote, PR, gate and compiler operation
is disposable or stubbed. Git's real merges, ancestry and pushes are retained.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

TOOL_ROOT = Path(__file__).resolve().parent.parent

GH = r'''#!/usr/bin/env python3
import json, os, re, subprocess, sys, time
from pathlib import Path
path = Path(os.environ['PROBE_STATE'])
s = json.loads(path.read_text())
a = sys.argv[1:]
blocking = os.environ.get('PROBE_GH_BLOCK')
if blocking and any(blocking in arg for arg in a):
    with Path(os.environ['PROBE_BLOCK_TRACE']).open('a') as trace:
        trace.write('gh ' + blocking + '\n')
    if os.environ.get('PROBE_BLOCK_CHILD'):
        subprocess.Popen([sys.executable,'-c','import time; time.sleep(2)'])
    time.sleep(2)
if os.environ.get('PROBE_IO_DELAY'):
    time.sleep(float(os.environ['PROBE_IO_DELAY']))
s.setdefault('gh_calls', []).append(a)
def done(value):
    path.write_text(json.dumps(s))
    print(json.dumps([value] if '--slurp' in a else value))
    sys.exit(0)
if a[:2] == ['repo', 'view']:
    path.write_text(json.dumps(s))
    print('fixture/x2c' if '--jq' in a else json.dumps({'nameWithOwner':'fixture/x2c'}))
    sys.exit(0)
if not a or a[0] != 'api':
    sys.exit('unexpected gh command: ' + repr(a))
method = 'GET'
for flag in ('--method', '-X'):
    if flag in a: method = a[a.index(flag)+1]
endpoint = next(x for x in a[1:] if x.startswith('repos/'))
body = {}
if '--input' in a:
    input_file = a[a.index('--input')+1]
    body = json.loads(sys.stdin.read() if input_file == '-' else Path(input_file).read_text())
for i, arg in enumerate(a[:-1]):
    if arg in ('-f','-F','--field','--raw-field'):
        key, value = a[i+1].split('=',1)
        if key == 'labels[]': body.setdefault('labels',[]).append(value)
        else: body[key] = value
        if method == 'GET': method = 'POST'
m = re.search(r'/(?:pulls|issues)/(\d+)', endpoint)
pr = s['pulls'].get(m.group(1)) if m else None
if '/events' in endpoint or '/timeline' in endpoint:
    done(pr.get('events',[]) if pr else [])
if '/labels' in endpoint:
    if endpoint.rstrip('/').endswith('/labels'):
        if method == 'GET': done(pr['labels'] if pr else [])
        if pr:
            for label in body.get('labels',[]):
                if not any(x['name'] == label for x in pr['labels']):
                    pr['labels'].append({'name':label})
                    pr.setdefault('events',[]).append({'event':'labeled','label':{'name':label},'created_at':'2026-01-01T00:00:00Z'})
        done(pr['labels'] if pr else body)
    if method == 'DELETE' and pr:
        label = endpoint.rsplit('/',1)[-1]
        pr['labels'] = [x for x in pr['labels'] if x['name'] != label]
    done({})
if '/pulls' in endpoint:
    if pr:
        if method in ('PATCH','POST'): pr.update(body)
        done(pr)
    done([p for p in s['pulls'].values() if p['state']=='open' and p['base']['ref']=='dev'])
if '/issues' in endpoint and pr:
    if method == 'PATCH': pr.update(body)
    done(pr)
sys.exit('unexpected gh endpoint: ' + endpoint)
'''

GATE = r'''#!/usr/bin/env python3
import hashlib, json, os, subprocess, sys
from pathlib import Path
root = Path.cwd()
p = Path(os.environ['PROBE_STATE'])
s = json.loads(p.read_text())
def identity():
    names = subprocess.check_output(['git','ls-files','-co','--exclude-standard','-z']).split(b'\0')
    h = hashlib.sha256()
    for name in sorted(set(names)):
        if not name: continue
        f = root / os.fsdecode(name)
        h.update(name)
        h.update(str(f.stat().st_mode).encode())
        h.update(f.read_bytes())
    return h.hexdigest()
receipt = root / 'debug' / 'probe-receipt.json'
command, target = sys.argv[1:3]
if command == 'check':
    sys.exit(0 if receipt.exists() and json.loads(receipt.read_text()) == {'target':target,'identity':identity()} else 1)
if receipt.exists() and json.loads(receipt.read_text()) == {'target':target,'identity':identity()}:
    print('valid'); sys.exit(0)
s.setdefault('gates',[]).append({'target':target,'root':str(root)})
mode = s.get('gate_failure')
if target == 'agent-pr-check':
    files = sorted((root/'src').glob('*.x'))
    (root/'bootstrap'/'src'/'compiled.c').write_text('generated: ' + '|'.join(f.read_text() for f in files))
if s.get('advance_on_gate'):
    subprocess.check_call(['git','--git-dir',s['remote'],'update-ref','refs/heads/dev',s.pop('advance_on_gate')])
if mode == 'ordinary' or mode == 'bootstrap_once':
    if mode == 'bootstrap_once': s.pop('gate_failure')
    p.write_text(json.dumps(s))
    print('[stage-diff-0] Error' if mode == 'bootstrap_once' else 'fixture test failure')
    sys.exit(1)
if s.get('authored_mutation'):
    (root/'src'/'surprise.x').write_text('unreviewed mutation\n')
receipt.parent.mkdir(exist_ok=True)
receipt.write_text(json.dumps({'target':target,'identity':identity()}))
p.write_text(json.dumps(s))
print('valid')
'''

MAKE = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p=Path(os.environ['PROBE_STATE']); s=json.loads(p.read_text())
s.setdefault('makes',[]).append({'args':sys.argv[1:],'root':str(Path.cwd())})
p.write_text(json.dumps(s))
if 'doc-generate' in sys.argv:
    for name in ('llms.txt','llms-full.txt'):
        path=Path('site/public')/name; path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text('generated documentation\n')
if 'build-safe' in sys.argv or 'build' in sys.argv:
    binary=Path('builds/0/x2c'); binary.parent.mkdir(parents=True,exist_ok=True)
    binary.write_text('#!/bin/sh\nexit 0\n'); binary.chmod(0o755)
'''


class IntegrationProbe(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='x2c-integration-probe-')
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.root = self.directory / 'plain-checkout'
        self.remote = self.directory / 'remote.git'
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        self.state_path = self.directory / 'github.json'
        self.state_path.write_text(json.dumps({'pulls':{},'remote':str(self.remote)}))
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ['PATH'],
                        PROBE_STATE=str(self.state_path), GIT_TERMINAL_PROMPT='0',
                        GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                        GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')
        self.write(self.bin/'gh', GH, executable=True)
        self.write(self.bin/'make', MAKE, executable=True)
        git_binary = shutil.which('git')
        git_wrapper = ('#!/usr/bin/env python3\n'
                       'import json, os, sys, time\nfrom pathlib import Path\n'
                       "blocking=os.environ.get('PROBE_GIT_BLOCK')\n"
                       "if blocking and blocking in sys.argv[1:]:\n"
                       "    with Path(os.environ['PROBE_BLOCK_TRACE']).open('a') as trace: trace.write('git '+blocking+'\\n')\n"
                       "    time.sleep(2)\n"
                       "p=Path(os.environ['PROBE_STATE']); s=json.loads(p.read_text())\n"
                       "s.setdefault('git_calls',[]).append(sys.argv[1:])\n"
                       'p.write_text(json.dumps(s))\n'
                       f'os.execv({git_binary!r}, [{git_binary!r}, *sys.argv[1:]])\n')
        self.write(self.bin/'git', git_wrapper, executable=True)
        self.command(['git','init','--bare',str(self.remote)], cwd=self.directory)
        self.command(['git','init','-b','dev',str(self.root)], cwd=self.directory)
        self.git('config','user.name','Fixture')
        self.git('config','user.email','fixture@example.invalid')
        self.git('remote','add','origin',str(self.remote))
        for name in ('integrate-dev.py','agent_context.py','land-dev','hooks/pre-push'):
            source = TOOL_ROOT/'tools'/name
            self.assertTrue(source.exists(), f'missing implementation tool: {source}')
            dest = self.root/'tools'/name
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(source,dest)
        self.write(self.root/'tools'/'gate-state.py',GATE,executable=True)
        shutil.copy2(TOOL_ROOT/'.gitignore',self.root/'.gitignore')
        self.write(self.root/'src'/'baseline.x','baseline\n')
        self.write(self.root/'bootstrap'/'src'/'compiled.c','seed\n')
        self.write(self.root/'docs'/'guide.md','old guide\n')
        self.git('add','.')
        self.git('commit','-qm','fixture baseline')
        self.base = self.git('rev-parse','HEAD').stdout.strip()
        self.git('push','-q','origin','HEAD:refs/heads/dev')
        self.cli('context','--role','integrator','--delivery','direct')

    @staticmethod
    def write(path, content, executable=False):
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(content)
        if executable: path.chmod(0o755)

    def command(self,args,cwd=None,ok=True,input=None):
        result=subprocess.run(args,cwd=cwd or self.root,env=self.env,input=input,
                              text=True,capture_output=True,timeout=30)
        if ok: self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        return result

    def git(self,*args,ok=True,cwd=None):
        return self.command(['git',*args],cwd=cwd,ok=ok)

    def cli(self,*args,ok=True):
        return self.command([sys.executable,str(self.root/'tools'/'integrate-dev.py'),
                         '--root',str(self.root),*map(str,args)],ok=ok)

    def state(self,**changes):
        value=json.loads(self.state_path.read_text())
        if changes:
            value.update(changes)
            self.state_path.write_text(json.dumps(value))
        return value

    def pr(self,number,path=None,content=None,base=None,depends=(),ready=True):
        self.git('checkout','-q','-B',f'work-{number}',base or self.base)
        self.write(self.root/(path or f'src/change-{number}.x'),content or f'change {number}\n')
        self.git('add','.')
        self.git('commit','-qm',f'fixture change {number}')
        head=self.git('rev-parse','HEAD').stdout.strip()
        self.git('push','-q','origin',f'HEAD:refs/pull/{number}/head')
        self.git('checkout','-q','dev')
        metadata={'version':1,'base':base or self.base,'head':head,
                  'dependencies':[{'pr':n,'head':h} for n,h in depends],
                  'evidence':[{'command':'fixture focused check','result':'passes'}],'notes':''}
        body='Authored explanation.\n<!-- x2c-integration:start -->\n```json\n'+json.dumps(metadata)+'\n```\n<!-- x2c-integration:end -->\n'
        pull={'number':number,'state':'open','draft':False,'body':body,
              'html_url':f'https://example.invalid/fixture/x2c/pull/{number}',
              'head':{'sha':head,'ref':f'work-{number}','repo':{'full_name':'fixture/x2c'}},
              'base':{'sha':self.base,'ref':'dev','repo':{'full_name':'fixture/x2c'}},
              'labels':[{'name':'integration-ready'}] if ready else [],
              'events':[{'event':'labeled','label':{'name':'integration-ready'},
                         'created_at':'2026-01-01T00:00:00Z'}] if ready else []}
        s=self.state(); s['pulls'][str(number)]=pull
        self.state_path.write_text(json.dumps(s))
        return head

    def record(self,batch=None):
        paths=sorted((self.root/'debug'/'integration').glob('*/batch.json'))
        self.assertTrue(paths,'prepare must retain a batch record')
        for path in paths:
            value=json.loads(path.read_text())
            if batch is None or value['id']==batch:
                return {**value,'_path':str(path)}
        self.fail(f'missing batch record: {batch}')

    def prepare(self,*args):
        result=self.cli('prepare','--flush',*args)
        record=json.loads(result.stdout)
        self.assertEqual(record['state'],'review',result.stdout)
        return record['id']

    def checkout(self,record):
        return Path(record['worktree'])

    def tip(self):
        return self.git('--git-dir',str(self.remote),'rev-parse','refs/heads/dev').stdout.strip()

    def assert_ancestor(self,revision):
        self.git('--git-dir',str(self.remote),'merge-base','--is-ancestor',revision,self.tip())

    def land(self,batch):
        result=self.cli('land',batch)
        value=json.loads(result.stdout)
        if value['state'] != 'gated':
            logs='\n'.join(Path(a['log']).read_text() for a in value['attempts'])
            self.fail(result.stdout+'\n'+logs)
        result=self.cli('land',batch,'--publish')
        self.assertEqual(json.loads(result.stdout)['state'],'landed',result.stdout)

    def test_context_preserves_conflicting_hooks_path(self):
        self.git('config','core.hooksPath','custom-hooks')
        result=self.cli('context','--role','individual','--delivery','direct',
                        ok=False)
        self.assertEqual(result.returncode,1,result.stdout+result.stderr)
        self.assertIn('conflicting core.hooksPath',result.stderr)
        self.assertEqual(self.git('config','--get','core.hooksPath').stdout.strip(),
                         'custom-hooks')

    def test_context_accepts_shared_hook_and_uses_pushing_worktree_policy(self):
        shared=self.directory/'common-hooks'
        shared.mkdir()
        hook=shared/'pre-push'
        shutil.copy2(self.root/'tools'/'hooks'/'pre-push',hook)
        self.git('config','core.hooksPath',str(shared))
        self.cli('context','--role','worker','--delivery','private')
        self.assertEqual(self.git('config','--get','core.hooksPath').stdout.strip(),
                         str(shared))
        result=self.command([str(hook)],input=(
            f'refs/heads/work {self.base} refs/heads/dev {self.base}\n'),ok=False)
        self.assertEqual(result.returncode,1,result.stderr)
        self.cli('context','--role','orchestrator','--delivery','direct')
        result=self.command([str(hook)],input=(
            f'refs/heads/work {self.base} refs/heads/dev {self.base}\n'))
        self.assertEqual(result.returncode,0,result.stderr)

    def test_context_refuses_changed_or_nonexecutable_shared_hook(self):
        shared=self.directory/'common-hooks'
        shared.mkdir()
        hook=shared/'pre-push'
        original=(self.root/'tools'/'hooks'/'pre-push').read_text()
        self.git('config','core.hooksPath',str(shared))
        for body,mode in [(original+'exit 0\n',0o755),(original,0o644)]:
            with self.subTest(mode=mode):
                hook.write_text(body)
                hook.chmod(mode)
                result=self.cli('context','--role','worker','--delivery','private',
                                ok=False)
                self.assertEqual(result.returncode,1,result.stdout+result.stderr)
                self.assertIn('conflicting core.hooksPath',result.stderr)
                self.assertEqual(
                    self.git('config','--get','core.hooksPath').stdout.strip(),
                    str(shared))

    def test_submit_preserves_prose_and_refreshes_readiness(self):
        head=self.pr(1)
        self.git('checkout','-q','work-1')
        self.cli('context','--role','individual','--delivery','pr')
        evidence=self.root/'debug'/'evidence.json'
        self.write(evidence,json.dumps([{'command':'specific fixture check','result':'passes'}]))
        self.cli('submit','--pr','1','--base',self.base,'--evidence-file',evidence)
        state=self.state(); pull=state['pulls']['1']
        self.assertTrue(pull['body'].startswith('Authored explanation.'))
        self.assertEqual(pull['body'].count('<!-- x2c-integration:start -->'),1)
        self.assertIn(head,pull['body'])
        self.assertEqual(pull['labels'],[{'name':'integration-ready'}])
        calls=state['gh_calls']
        delete=next(i for i,c in enumerate(calls) if 'DELETE' in c)
        patch=next(i for i,c in enumerate(calls) if 'PATCH' in c)
        add=max(i for i,c in enumerate(calls) if 'POST' in c)
        self.assertLess(delete,patch); self.assertLess(patch,add)
        self.assertEqual(state.get('gates',[]),[])

    def test_submission_notes_are_ignored_but_authored_files_are_not(self):
        self.pr(1)
        self.git('checkout','-q','work-1')
        self.cli('context','--role','individual','--delivery','pr')
        evidence=self.root/'.context'/'submission'/'evidence.json'
        self.write(evidence,json.dumps([{'command':'focused check','result':'pass'}]))
        self.cli('submit','--pr','1','--base',self.base,'--evidence-file',evidence)
        self.write(self.root/'src'/'unreviewed.x','new source\n')
        result=self.cli('submit','--pr','1','--base',self.base,
                        '--evidence-file',evidence,ok=False)
        self.assertEqual(result.returncode,1,result.stdout+result.stderr)
        self.assertIn('commit the authored changes',result.stderr)

    def test_submission_during_gate_keeps_integration_owner_lock(self):
        head=self.pr(1,ready=False)
        submitting=self.directory/'independent-pr-worktree'
        self.git('worktree','add',str(submitting),'work-1')
        tool=submitting/'tools'/'integrate-dev.py'
        self.command([sys.executable,str(tool),'--root',str(submitting),
                      'context','--role','individual','--delivery','pr'],
                     cwd=submitting)
        evidence=submitting/'debug'/'evidence.json'
        self.write(evidence,json.dumps([{'command':'focused check','result':'passed'}]))
        lock=self.root/'.git'/'integration.lock'
        with lock.open('a+') as holder:
            fcntl.flock(holder,fcntl.LOCK_EX|fcntl.LOCK_NB)
            holder.write(str(os.getpid())); holder.flush()
            submitted=self.command(
                [sys.executable,str(tool),'--root',str(submitting),'submit',
                 '--pr','1','--base',self.base,'--evidence-file',str(evidence)],
                cwd=submitting,ok=False)
            self.assertEqual(submitted.returncode,0,
                             submitted.stdout+submitted.stderr)
            self.assertEqual(json.loads(submitted.stdout)['head'],head)
            second=self.cli('prepare','--flush',ok=False)
            self.assertNotEqual(second.returncode,0)
            self.assertIn('another coordinator command is active',second.stderr)
        self.assertEqual(self.state()['pulls']['1']['labels'],
                         [{'name':'integration-ready'}])
        self.assertEqual(self.tip(),self.base)
        self.assertEqual(self.state().get('gates',[]),[])

    def test_malformed_metadata_does_not_block_good_ready_work(self):
        self.pr(1); bad_evidence_head=self.pr(2); self.pr(3)
        state=self.state()
        invalid=[[], {'version':1,'base':self.base,'head':bad_evidence_head,
                      'dependencies':[],'evidence':['invalid evidence'],'notes':''}]
        for number,value in zip(('1','2'),invalid):
            state['pulls'][number]['body']=(
                '<!-- x2c-integration:start -->\n```json\n'+json.dumps(value)+
                '\n```\n<!-- x2c-integration:end -->')
        self.state_path.write_text(json.dumps(state))
        status=json.loads(self.cli('status').stdout)
        self.assertEqual([p['number'] for p in status['ready']],[3])
        self.assertEqual({p['number'] for p in status['pending']},{1,2})
        batch=self.prepare()
        self.assertEqual([p['number'] for p in self.record(batch)['prs']],[3])
        self.assertEqual(self.state().get('gates',[]),[])

    def test_explicit_selection_fails_atomically_for_missing_or_held_pr(self):
        self.pr(1); self.pr(2)
        state=self.state(); state['pulls']['2']['draft']=True
        self.state_path.write_text(json.dumps(state))
        for unavailable in ('99','2'):
            with self.subTest(unavailable=unavailable):
                result=self.cli('prepare','--flush','--prs','1',unavailable,ok=False)
                self.assertNotEqual(result.returncode,0)
                self.assertIn('explicit batch cannot be assembled',result.stderr)
                status=json.loads(self.cli('status').stdout)
                self.assertIsNone(status['active'])
                self.assertEqual(status['batches'],[])
        self.assertEqual(self.tip(),self.base)
        self.assertEqual(self.state().get('gates',[]),[])

    def test_collection_uses_oldest_submission_before_dependency_ordering(self):
        dependency=self.pr(1)
        self.pr(2,base=dependency,depends=[(1,dependency)])
        state=self.state()
        state['pulls']['1']['events'][0]['created_at']=(
            dt.datetime.now(dt.timezone.utc).isoformat())
        self.state_path.write_text(json.dumps(state))
        result=json.loads(self.cli('prepare','--window','300').stdout)
        self.assertEqual(result.get('state'),'review',result)
        self.assertEqual([p['number'] for p in result['prs']],[1,2])
        self.assertEqual(self.state().get('gates',[]),[])

    def test_missing_dependency_waits_without_creating_candidate(self):
        self.pr(1,depends=[(99,'0'*40)])
        result=json.loads(self.cli('prepare','--flush').stdout)
        self.assertEqual(result['ready'],[])
        self.assertIn('dependency',result['pending'][0]['reason'])
        self.assertEqual(self.tip(),self.base)
        self.assertEqual(self.state().get('gates',[]),[])

    def test_conflict_preserves_candidate_and_requires_resolution(self):
        self.pr(1,'src/shared.x','first intent\n')
        self.pr(2,'src/shared.x','second intent\n')
        record=json.loads(self.cli('prepare','--flush').stdout)
        self.assertEqual(record['state'],'needs-attention')
        candidate=Path(record['worktree'])
        self.assertTrue(self.git('rev-parse','--verify','MERGE_HEAD',cwd=candidate).stdout)
        self.assertIn('<<<<<<<',(candidate/'src/shared.x').read_text())
        self.assertEqual(self.tip(),self.base)
        self.assertEqual(self.state().get('gates',[]),[])
        self.assertNotEqual(self.cli('land',record['id'],ok=False).returncode,0)

    def test_upstream_changes_during_gate_never_pushes(self):
        self.pr(1); batch=self.prepare()
        self.git('checkout','-q','-B','external',self.base)
        self.write(self.root/'src/external.x','outside change\n')
        self.git('add','.'); self.git('commit','-qm','fixture outside advance')
        advance=self.git('rev-parse','HEAD').stdout.strip()
        self.git('push','-q','origin','HEAD:refs/heads/external')
        self.git('checkout','-q','dev')
        self.state(advance_on_gate=advance)
        result=json.loads(self.cli('land',batch).stdout)
        self.assertIn(result['state'],{'gated','needs-attention'})
        result=json.loads(self.cli('land',batch,'--publish').stdout)
        self.assertEqual(result['state'],'review')
        self.assertEqual(self.tip(),advance)
        self.assertEqual(len(self.state()['gates']),1)

    def test_multi_pr_one_gate_includes_generated_output(self):
        heads=[self.pr(1),self.pr(2)]
        batch=self.prepare(); self.land(batch)
        for head in heads: self.assert_ancestor(head)
        self.assertEqual(len(self.state().get('gates',[])),1)
        generated=self.git('--git-dir',str(self.remote),'show','dev:bootstrap/src/compiled.c').stdout
        self.assertIn('change 1',generated); self.assertIn('change 2',generated)
        self.assertFalse(any(p['labels'] for p in self.state()['pulls'].values()))

    def test_mixed_and_unknown_documentation_paths_use_code_gate(self):
        self.pr(1,'docs/guide.md','new guide\n')
        self.pr(2,'docs/checker.sh','echo executable documentation helper\n')
        batch=self.prepare(); self.land(batch)
        self.assertEqual([g['target'] for g in self.state()['gates']],['agent-pr-check'])

    def test_documentation_batch_uses_only_doc_gate(self):
        head=self.pr(1,'docs/guide.md','new guide\n')
        batch=self.prepare(); self.land(batch)
        self.assert_ancestor(head)
        self.assertEqual([g['target'] for g in self.state()['gates']],['doc-check'])

    def test_generated_llms_text_uses_doc_generation_and_doc_gate(self):
        self.pr(1,'site/public/llms.txt','stale generated documentation\n')
        batch=self.prepare(); self.land(batch)
        state=self.state()
        self.assertEqual([g['target'] for g in state['gates']],['doc-check'])
        self.assertTrue(any('doc-generate' in call['args']
                            for call in state['makes']))
        generated=self.git('--git-dir',str(self.remote),
                           'show','dev:site/public/llms.txt').stdout
        self.assertEqual(generated,'generated documentation\n')

    def test_success_clears_failure_reason_and_keeps_attempt_history(self):
        self.pr(1); self.state(gate_failure='ordinary')
        batch=self.prepare()
        failed=self.cli('land',batch,ok=False)
        failure=json.loads(failed.stdout)
        self.assertEqual(failure['state'],'needs-attention')
        old_reason=failure['reason']
        candidate=Path(failure['worktree'])
        self.git('checkout','--','bootstrap/src/compiled.c',cwd=candidate)
        self.state(gate_failure=None)
        gated=json.loads(self.cli('land',batch).stdout)
        self.assertEqual(gated['state'],'gated')
        self.assertNotIn('reason',gated)
        self.assertTrue(old_reason)
        self.assertEqual([attempt['returncode'] for attempt in gated['attempts']],
                         [1,0])
        candidate=Path(gated['worktree'])
        self.git('push','-q','origin','HEAD:refs/heads/dev',cwd=candidate)
        landed=json.loads(self.cli('land',batch,'--publish').stdout)
        self.assertEqual(landed['state'],'landed')
        self.assertNotIn('reason',landed)
        self.assertEqual(len(landed['attempts']),2)

    def test_publication_lock_rejects_legacy_directory_without_removing_it(self):
        common=self.directory/'legacy-git-common'
        lock=common/'land-dev.lock'; lock.mkdir(parents=True)
        pid=lock/'pid'; pid.write_text('99999999\n')
        script=TOOL_ROOT/'tools'/'land-dev'
        import importlib.machinery, importlib.util
        sys.path.insert(0,str(TOOL_ROOT/'tools'))
        loader=importlib.machinery.SourceFileLoader('land_dev_probe',str(script))
        spec=importlib.util.spec_from_loader('land_dev_probe',loader)
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        module.git=lambda *args: str(common)
        with self.assertRaisesRegex(ValueError,'legacy publication lock'):
            module.acquire_lock()
        self.assertEqual(pid.read_text(),'99999999\n')

    def test_publication_lock_excludes_a_second_process_and_releases_on_exit(self):
        common=self.directory/'lock-git-common'; common.mkdir()
        script=TOOL_ROOT/'tools'/'land-dev'
        child=r'''import importlib.machinery, importlib.util, sys, time
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1]).parent))
loader=importlib.machinery.SourceFileLoader('land_dev_probe',sys.argv[1])
spec=importlib.util.spec_from_loader('land_dev_probe',loader)
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
module.git=lambda *args: sys.argv[2]
lock=module.acquire_lock()
print('acquired',flush=True)
time.sleep(float(sys.argv[3]))
if hasattr(lock,'close'): lock.close()
'''
        holder=subprocess.Popen([sys.executable,'-c',child,str(script),
                                 str(common),'30'],stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE,text=True)
        self.addCleanup(lambda: holder.poll() is None and holder.terminate())
        try:
            self.assertEqual(holder.stdout.readline().strip(),'acquired')
            started=time.monotonic()
            waiter=subprocess.run([sys.executable,'-c',child,str(script),
                                   str(common),'0'],capture_output=True,text=True,
                                  timeout=2)
            self.assertLess(time.monotonic()-started,2)
            self.assertNotEqual(waiter.returncode,0,waiter.stdout+waiter.stderr)
            self.assertIn('another publisher is active',waiter.stderr)
        finally:
            holder.terminate(); holder.wait(timeout=5)
            holder.stdout.close(); holder.stderr.close()
        released=subprocess.run([sys.executable,'-c',child,str(script),
                                 str(common),'0'],capture_output=True,text=True,
                                timeout=2)
        self.assertEqual(released.returncode,0,released.stdout+released.stderr)

    def test_gate_failure_never_pushes(self):
        self.pr(1); self.state(gate_failure='ordinary')
        batch=self.prepare()
        result=self.cli('land',batch,ok=False)
        self.assertEqual(json.loads(result.stdout)['state'],'needs-attention')
        self.assertEqual(self.tip(),self.base)
        self.assertNotEqual(self.cli('land',batch,'--publish',ok=False).returncode,0)
        self.assertEqual(self.tip(),self.base)
        self.assertEqual(len(self.state().get('gates',[])),1)

    def test_bootstrap_second_round_is_bounded(self):
        self.pr(1); self.state(gate_failure='bootstrap_once')
        batch=self.prepare(); self.land(batch)
        self.assertEqual(len(self.state()['gates']),2)

    def test_changed_head_and_withdrawal_stop_before_push(self):
        for change in ('head','label'):
            with self.subTest(change=change):
                if change=='label':
                    self.cli('park',batch)
                    self.pr(2)
                    batch=self.prepare('--prs','2')
                else:
                    self.pr(1); batch=self.prepare()
                self.cli('land',batch)
                s=self.state(); number='1' if change=='head' else '2'
                if change=='head': s['pulls'][number]['head']['sha']='0'*40
                else: s['pulls'][number]['labels']=[]
                self.state_path.write_text(json.dumps(s))
                self.assertNotEqual(self.cli('land',batch,'--publish',ok=False).returncode,0)
                self.assertEqual(self.tip(),self.base)

    def test_dependencies_preserve_pinned_ancestry(self):
        first=self.pr(1)
        second=self.pr(2,base=first,depends=[(1,first)])
        batch=self.prepare(); self.land(batch)
        self.assert_ancestor(first); self.assert_ancestor(second)
        self.assertEqual(len(self.state()['gates']),1)

    def test_parked_revisions_are_held(self):
        self.pr(1); batch=self.prepare(); self.cli('park',batch)
        self.pr(2); another=self.prepare()
        record=self.record(another)
        candidate=self.checkout(record)
        first=self.state()['pulls']['1']['head']['sha']
        self.assertNotEqual(self.git('merge-base','--is-ancestor',first,'HEAD',cwd=candidate,ok=False).returncode,0)

    def test_retry_preserves_candidate_repairs_and_frozen_prs(self):
        self.pr(1); batch=self.prepare()
        original=self.record(batch); candidate=self.checkout(original)
        self.write(candidate/'src/repair.x','candidate-local repair\n')
        self.git('add','.',cwd=candidate)
        self.git('commit','-qm','fixture integration repair',cwd=candidate)
        repaired=self.git('rev-parse','HEAD',cwd=candidate).stdout.strip()
        self.cli('park',batch)
        self.pr(2)
        retried=self.prepare('--retry',batch)
        record=self.record(retried)
        self.assertEqual(retried,batch)
        self.assertEqual(record['worktree'],original['worktree'])
        self.assertEqual(record['prs'],original['prs'])
        self.assertEqual(record['candidate'],repaired)
        self.assertEqual(record['attempts'],original['attempts'])
        self.assertEqual(len(list((self.root/'debug'/'integration').glob(
            '*/batch.json'))),1)
        self.cli('park',batch)
        status=json.loads(self.cli('status').stdout)
        self.assertEqual([p['number'] for p in status['ready']],[2])
        self.assertEqual([p['number'] for p in status['pending']],[1])
        self.assertEqual(self.tip(),self.base)
        self.assertEqual(self.state().get('gates',[]),[])

    def test_retry_does_not_release_holds_with_another_active_batch(self):
        self.pr(1); parked=self.prepare(); self.cli('park',parked)
        self.pr(2); active=self.prepare()
        before=self.record(parked)
        result=self.cli('prepare','--retry',parked,ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('active batch',result.stderr)
        self.assertEqual(self.record(parked),before)
        status=json.loads(self.cli('status').stdout)
        self.assertEqual(status['active']['id'],active)
        self.assertIn(1,[p['number'] for p in status['pending']])

    def test_retry_rejects_changed_or_withdrawn_pr_atomically(self):
        self.pr(1); batch=self.prepare(); self.cli('park',batch)
        before=self.record(batch); original=self.state()
        for change in ('head','label'):
            with self.subTest(change=change):
                state=json.loads(json.dumps(original))
                if change=='head': state['pulls']['1']['head']['sha']='0'*40
                else: state['pulls']['1']['labels']=[]
                self.state_path.write_text(json.dumps(state))
                result=self.cli('prepare','--retry',batch,ok=False)
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(self.record(batch),before)
        self.assertEqual(self.tip(),self.base)
        self.assertEqual(self.state().get('gates',[]),[])

    def test_retry_rejects_different_explicit_selection(self):
        self.pr(1); batch=self.prepare(); self.cli('park',batch)
        self.pr(2); before=self.record(batch)
        result=self.cli('prepare','--retry',batch,'--prs','1','2',ok=False)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.record(batch),before)
        self.assertEqual(self.prepare('--retry',batch,'--prs','1'),batch)

    def test_upstream_advancement_requires_new_review(self):
        self.pr(1); batch=self.prepare()
        self.git('checkout','-q','-B','external',self.base)
        self.write(self.root/'src/external.x','outside change\n')
        self.git('add','.'); self.git('commit','-qm','fixture outside advance')
        advanced=self.git('rev-parse','HEAD').stdout.strip()
        self.git('push','-q','origin','HEAD:refs/heads/dev')
        self.git('checkout','-q','dev')
        result=self.cli('land',batch,ok=False)
        self.assertEqual(json.loads(result.stdout)['state'],'review')
        self.assertIn('dev advanced',json.loads(result.stdout)['reason'])
        self.assertEqual(self.tip(),advanced)
        self.assertEqual(self.state().get('gates',[]),[])

    def test_crash_after_push_reconciles_without_repeating_work(self):
        head=self.pr(1); batch=self.prepare(); self.cli('land',batch)
        candidate=self.checkout(self.record(batch))
        self.git('push','-q','origin','HEAD:refs/heads/dev',cwd=candidate)
        before=self.state()
        pushes=sum('push' in call for call in before['git_calls'])
        gates=len(before['gates'])
        landed=self.tip()
        self.cli('land',batch,'--publish')
        self.assertEqual(self.tip(),landed)
        self.assert_ancestor(head)
        after=self.state()
        self.assertEqual(sum('push' in call for call in after['git_calls']),pushes)
        self.assertEqual(len(after['gates']),gates)

    def test_generated_conflict_can_resume_after_owner_resolution(self):
        heads=[self.pr(1,'bootstrap/src/compiled.c','first generated output\n'),
               self.pr(2,'bootstrap/src/compiled.c','second generated output\n')]
        record=json.loads(self.cli('prepare','--flush').stdout)
        self.assertEqual(record['state'],'needs-attention')
        candidate=Path(record['worktree'])
        self.write(candidate/'bootstrap/src/compiled.c','fixture regenerated seed\n')
        self.git('add','bootstrap/src/compiled.c',cwd=candidate)
        self.git('commit','-qm','resolve generated output from owner',cwd=candidate)
        batch=self.prepare(); self.land(batch)
        for head in heads: self.assert_ancestor(head)
        self.assertEqual(len(self.state()['gates']),1)
        generated=self.git('--git-dir',str(self.remote),'show','dev:bootstrap/src/compiled.c').stdout
        self.assertEqual(generated,'generated: baseline\n')

    def test_gate_cannot_silently_commit_unexpected_authored_changes(self):
        self.pr(1); self.state(authored_mutation=True)
        batch=self.prepare()
        result=json.loads(self.cli('land',batch).stdout)
        self.assertEqual(result['state'],'needs-attention')
        self.assertEqual(self.tip(),self.base)
        candidate=self.checkout(result)
        self.assertTrue((candidate/'src/surprise.x').exists())

    def test_completed_gate_recovery_runs_no_make_work(self):
        self.pr(1); batch=self.prepare(); self.cli('land',batch)
        record=self.record(batch)
        self.assertEqual(record['state'],'gated')
        candidate=self.checkout(record)
        helper_review=candidate/'debug'/'land-dev-review.json'
        self.assertTrue(helper_review.is_file())
        reviewed_artifacts=helper_review.read_text()
        before=self.state()
        path=Path(record.pop('_path'))
        record['state']='gating'; record.pop('gated',None)
        path.write_text(json.dumps(record))
        recovered=json.loads(self.cli('land',batch).stdout)
        self.assertEqual(recovered['state'],'gated')
        self.assertNotIn('reason',recovered)
        self.assertEqual(len(recovered['attempts']),len(record['attempts']))
        self.assertEqual(helper_review.read_text(),reviewed_artifacts)
        after=self.state()
        self.assertEqual(after['makes'],before['makes'])
        self.assertEqual(after['gates'],before['gates'])
        self.assertEqual(self.tip(),self.base)
        self.cli('land',batch,'--publish')
        self.assertEqual(len(self.state()['gates']),1)

    def test_wait_budget_bounds_git_and_gh_io(self):
        self.pr(1)
        for variable, value in [('PROBE_GIT_BLOCK','rev-parse'),
                                ('PROBE_GIT_BLOCK','fetch'),
                                ('PROBE_GH_BLOCK','repo'),
                                ('PROBE_GH_BLOCK','pulls?'),
                                ('PROBE_GH_BLOCK','/events')]:
            with self.subTest(variable=variable,value=value):
                self.env[variable]=value
                if value == '/events': self.env['PROBE_BLOCK_CHILD']='1'
                trace=self.root/'debug'/'blocking-io.log'
                trace.unlink(missing_ok=True)
                self.env['PROBE_BLOCK_TRACE']=str(trace)
                started=time.monotonic()
                budget=1.5 if value == '/events' else 0.75
                result=self.cli('wait','--timeout',str(budget),'--flush')
                elapsed=time.monotonic()-started
                self.env.pop(variable)
                self.env.pop('PROBE_BLOCK_CHILD',None)
                self.assertLess(elapsed,budget+0.55,result.stdout+result.stderr)
                self.assertIn(value,trace.read_text())
                value=json.loads(result.stdout)
                self.assertTrue(value['timed_out'])
                self.assertEqual(value['ready'],[])
        self.assertEqual(self.tip(),self.base)
        self.assertEqual(self.state().get('gates',[]),[])

    def test_wait_budget_includes_dependency_ancestry_checks(self):
        first=self.pr(1)
        self.pr(2,base=first,depends=[(1,first)])
        self.env['PROBE_GIT_BLOCK']='merge-base'
        trace=self.root/'debug'/'blocking-io.log'
        self.env['PROBE_BLOCK_TRACE']=str(trace)
        started=time.monotonic()
        result=self.cli('wait','--timeout','1.5','--flush')
        elapsed=time.monotonic()-started
        self.env.pop('PROBE_GIT_BLOCK')
        self.assertLess(elapsed,2.05,result.stdout+result.stderr)
        self.assertIn('merge-base',trace.read_text())
        self.assertTrue(json.loads(result.stdout)['timed_out'])
        self.assertEqual(self.tip(),self.base)

    def test_wait_io_uses_one_overall_budget_and_retains_pending(self):
        self.pr(1); self.pr(2)
        state=self.state(); state['pulls']['1']['draft']=True
        self.state_path.write_text(json.dumps(state))
        self.env['PROBE_GH_BLOCK']='/events'
        self.env['PROBE_BLOCK_TRACE']=str(self.root/'debug'/'blocking-io.log')
        result=self.cli('wait','--timeout','1.5','--flush')
        self.env.pop('PROBE_GH_BLOCK')
        value=json.loads(result.stdout)
        self.assertTrue(value['timed_out'])
        self.assertEqual(value['ready'],[])
        self.assertEqual([p['number'] for p in value['pending']],[1])
        self.env['PROBE_IO_DELAY']='0.15'
        started=time.monotonic()
        result=self.cli('wait','--timeout','0.25','--flush')
        elapsed=time.monotonic()-started
        self.env.pop('PROBE_IO_DELAY')
        self.assertLess(elapsed,1,result.stdout+result.stderr)
        self.assertTrue(json.loads(result.stdout)['timed_out'])

    def test_zero_timeout_is_one_poll_with_bounded_io(self):
        started=time.monotonic()
        result=self.cli('wait','--timeout','0')
        self.assertLess(time.monotonic()-started,3,result.stdout+result.stderr)
        value=json.loads(result.stdout)
        self.assertEqual(value['ready'],[])
        self.assertFalse(value['timed_out'])
        state=self.state()
        self.assertEqual(sum('fetch' in call for call in state['git_calls']),1)

    def test_provider_neutral_push_guard(self):
        for role,delivery,blocked in [('worker','direct',True),('individual','pr',True),
                                      ('orchestrator','pr',True),('individual','direct',False),
                                      ('integrator','direct',False)]:
            with self.subTest(role=role,delivery=delivery):
                self.cli('context','--role',role,'--delivery',delivery)
                hook=self.command([str(self.root/'tools'/'hooks'/'pre-push')],
                              input='refs/heads/dev '+self.base+' refs/heads/dev '+self.base+'\n',ok=False)
                self.assertEqual(hook.returncode!=0,blocked)
                pr_hook=self.command([str(self.root/'tools'/'hooks'/'pre-push')],
                                input='refs/heads/work '+self.base+' refs/heads/work '+self.base+'\n',ok=False)
                self.assertEqual(pr_hook.returncode,0,pr_hook.stderr)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-root',type=Path,default=TOOL_ROOT,
                        help='checkout containing the implementation under test')
    args,unittest_args=parser.parse_known_args()
    TOOL_ROOT=args.tool_root.resolve()
    unittest.main(argv=[sys.argv[0],*unittest_args],verbosity=2)
