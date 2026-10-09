import json,sys,glob,os
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*.jsonl'))):
    for line in open(f):
        try: o=json.loads(line)
        except Exception: continue
        m=o.get('message') or {}
        c=m.get('content')
        if isinstance(c,str):
            if o.get('type')=='user': print('USER:',c.split('\n')[0][:600]); print()
            continue
        for b in c or []:
            if b.get('type')=='text' and o.get('type')=='user': print('USER:',b['text'].split('\n')[0][:600]); print()
            if b.get('type')=='tool_use': print('TOOL_USE:',json.dumps(b.get('input'))[:900])
            if b.get('type')=='tool_result':
                r=b.get('content'); r=r if isinstance(r,str) else json.dumps(r)
                print('RESULT(err=%s):'%b.get('is_error'), r[:700]); print()
