from pathlib import Path
p=Path('worker/command_center_period.js')
t=p.read_text(encoding='utf-8')
repls={
"scopeDepartment ? [scopeDepartment] : []":"scopeValue ? [scopeValue] : []",
"scopeDepartment\n      ? [rangeStartIso, rangeEndIso, scopeDepartment]\n      : [rangeStartIso, rangeEndIso]":"scopeValue\n      ? [rangeStartIso, rangeEndIso, scopeValue]\n      : [rangeStartIso, rangeEndIso]",
"scopeDepartment ? [from, to, scopeDepartment] : [from, to]":"scopeValue ? [from, to, scopeValue] : [from, to]",
"scopeDepartment ? [liveSince, scopeDepartment] : [liveSince]":"scopeValue ? [liveSince, scopeValue] : [liveSince]",
}
for old,new in repls.items():
    n=t.count(old)
    if n<1: raise SystemExit(f'missing binding pattern: {old}')
    t=t.replace(old,new)
p.write_text(t,encoding='utf-8')
