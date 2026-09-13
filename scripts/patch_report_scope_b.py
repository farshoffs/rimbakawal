from pathlib import Path
p=Path('lib/features/admin/report_screen.dart')
t=p.read_text(encoding='utf-8')
old="""                  const SizedBox(height: 18),
                  DropdownButtonFormField<int?>("""
new="""                  const SizedBox(height: 18),
                  if (!isCompanyAdmin) ...[
                    DropdownButtonFormField<int>(
                      key: ValueKey('report-company-${scopedCompanyId ?? -1}'),
                      initialValue: scopedCompanyId ?? -1,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Syarikat',
                        prefixIcon: Icon(Icons.business_rounded),
                      ),
                      items: [
                        const DropdownMenuItem<int>(value: -1, child: Text('Semua Syarikat')),
                        ...companies.map((company) => DropdownMenuItem<int>(
                          value: company.id,
                          child: Text(company.name),
                        )),
                      ],
                      onChanged: _loadingDepartments || _generating
                          ? null
                          : (value) {
                              _scope.setCompany(value == null || value == -1 ? null : value);
                              setState(() => _departmentId = null);
                            },
                    ),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<int?>("""
if t.count(old)!=1: raise SystemExit(f'company dropdown {t.count(old)}')
t=t.replace(old,new,1)
if t.count("                      ..._departments.map(")!=1: raise SystemExit('school options')
t=t.replace("                      ..._departments.map(","                      ...scopedDepartments.map(",1)
old2="""                    onChanged: _loadingDepartments || _generating
                        ? null
                        : (value) => setState(() => _departmentId = value),"""
new2="""                    onChanged: _loadingDepartments || _generating
                        ? null
                        : (value) {
                            if (!isCompanyAdmin) _scope.setDepartment(value);
                            setState(() => _departmentId = value);
                          },"""
if t.count(old2)!=1: raise SystemExit(f'school change {t.count(old2)}')
p.write_text(t.replace(old2,new2,1),encoding='utf-8')
