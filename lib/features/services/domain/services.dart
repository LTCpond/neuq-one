import 'package:material_ui/material_ui.dart';

import '../../../core/network/campus_access/campus_resource.dart';

class CampusService {
  const CampusService.website(this.name, this.icon, String target)
    : url = target,
      route = null;
  const CampusService.inApp(this.name, this.icon, String target)
    : route = target,
      url = null;

  final String name;
  final IconData icon;
  final String? url;
  final String? route;
}

const classroomsService = CampusService.inApp(
  '空教室',
  Icons.meeting_room_outlined,
  '/services/classrooms',
);
const campusCardService = CampusService.inApp(
  '校园卡',
  Icons.credit_card_outlined,
  '/services/campus-card',
);

const campusMailService = CampusService.inApp(
  '校园邮箱',
  Icons.mail_outline_rounded,
  '/services/mail',
);
const employmentService = CampusService.inApp(
  '宣讲会与招聘会',
  Icons.work_outline_rounded,
  '/services/employment',
);
const schoolPoliciesService = CampusService.inApp(
  '学校政策',
  Icons.description_outlined,
  '/services/policies',
);

const academicServices = [
  CampusService.website(
    '教务系统',
    Icons.school_outlined,
    'https://jwxt.neuq.edu.cn/eams/localLogin.action',
  ),
  CampusService.inApp('校园地图', Icons.map_outlined, '/services/campus-map'),
];

const accessServices = [
  CampusService.website(
    '一网通办',
    Icons.apps_rounded,
    'https://eone.neuq.edu.cn/',
  ),
  CampusService.website(
    '校园网',
    Icons.wifi_rounded,
    'https://ipgate.neuq.edu.cn/',
  ),
];

const webVpnService = CampusService.website(
  'WebVPN',
  Icons.vpn_lock_outlined,
  officialWebVpnUrl,
);
