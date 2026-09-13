import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';

class AdminScopeState extends ChangeNotifier {
  AdminScopeState._();

  static final AdminScopeState instance = AdminScopeState._();

  int? companyId;
  int? departmentId;

  int? effectiveCompanyId(List<CompanyRecord> companies) {
    final value = companyId;
    if (value == null) return null;
    return companies.any((item) => item.id == value) ? value : null;
  }

  int? effectiveDepartmentId(List<DepartmentRecord> departments) {
    final value = departmentId;
    if (value == null) return null;
    return departments.any((item) => item.id == value) ? value : null;
  }

  void setCompany(int? value) {
    if (companyId == value && departmentId == null) return;
    companyId = value;
    departmentId = null;
    notifyListeners();
  }

  void setDepartment(int? value) {
    if (departmentId == value) return;
    departmentId = value;
    notifyListeners();
  }

  void clear() {
    if (companyId == null && departmentId == null) return;
    companyId = null;
    departmentId = null;
    notifyListeners();
  }
}

class AdminScopeFilterBar extends StatelessWidget {
  const AdminScopeFilterBar({
    required this.companies,
    required this.departments,
    this.showCompany = true,
    this.showSchool = true,
    this.onChanged,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<CompanyRecord> companies;
  final List<DepartmentRecord> departments;
  final bool showCompany;
  final bool showSchool;
  final VoidCallback? onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scope = AdminScopeState.instance;
    return AnimatedBuilder(
      animation: scope,
      builder: (context, _) {
        final companyId = scope.effectiveCompanyId(companies);
        final companyDepartments = companyId == null
            ? departments
            : departments
                  .where((item) => item.companyId == companyId)
                  .toList();
        final departmentId = scope.effectiveDepartmentId(companyDepartments);

        Widget companyField() => DropdownButtonFormField<int>(
          key: ValueKey('admin-company-scope-${companyId ?? -1}'),
          initialValue: companyId ?? -1,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Syarikat',
            prefixIcon: Icon(Icons.business_rounded),
          ),
          items: [
            const DropdownMenuItem<int>(
              value: -1,
              child: Text('Semua Syarikat'),
            ),
            ...companies.where((item) => item.active).map(
              (company) => DropdownMenuItem<int>(
                value: company.id,
                child: Text(company.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (value) {
            scope.setCompany(value == null || value == -1 ? null : value);
            onChanged?.call();
          },
        );

        Widget schoolField() => DropdownButtonFormField<int>(
          key: ValueKey(
            'admin-school-scope-${companyId ?? -1}-${departmentId ?? -1}',
          ),
          initialValue: departmentId ?? -1,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Sekolah',
            prefixIcon: Icon(Icons.school_rounded),
          ),
          items: [
            const DropdownMenuItem<int>(
              value: -1,
              child: Text('Semua Sekolah'),
            ),
            ...companyDepartments.where((item) => item.active).map(
              (department) => DropdownMenuItem<int>(
                value: department.id,
                child: Text(department.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (value) {
            scope.setDepartment(value == null || value == -1 ? null : value);
            onChanged?.call();
          },
        );

        final fields = <Widget>[
          if (showCompany) companyField(),
          if (showSchool) schoolField(),
        ];
        if (fields.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (fields.length == 1 || constraints.maxWidth < 620) {
                return Column(
                  children: [
                    for (var i = 0; i < fields.length; i++) ...[
                      fields[i],
                      if (i != fields.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1]),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

List<CompanyRecord> companiesFromDepartments(
  List<DepartmentRecord> departments,
) {
  final byId = <int, CompanyRecord>{};
  for (final department in departments) {
    final id = department.companyId;
    if (id == null || department.companyName.trim().isEmpty) continue;
    byId[id] = CompanyRecord(
      id: id,
      name: department.companyName,
      active: true,
    );
  }
  final result = byId.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}
