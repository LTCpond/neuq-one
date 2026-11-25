import 'package:material_ui/material_ui.dart';

class CampusService {
  const CampusService.website(this.id, this.name, this.icon, String target)
    : url = target,
      route = null;
  const CampusService.inApp(this.id, this.name, this.icon, String target)
    : route = target,
      url = null;

  final String id;
  final String name;
  final IconData icon;
  final String? url;
  final String? route;
}

const classroomsService = CampusService.inApp(
  'classrooms',
  '空教室',
  Icons.meeting_room_outlined,
  '/services/classrooms',
);
const campusCardService = CampusService.inApp(
  'campus-card',
  '校园卡',
  Icons.credit_card_outlined,
  '/services/campus-card',
);

const campusServiceGroups = {
  '教学': [
    CampusService.website(
      'academic',
      '教务系统',
      Icons.school_outlined,
      'https://jwxt.neuq.edu.cn/eams/localLogin.action',
    ),
    CampusService.website(
      'map',
      '校园地图',
      Icons.map_outlined,
      'https://yx.neuq.edu.cn/shgl/xxdt.htm',
    ),
  ],
  '办事与访问': [
    CampusService.website(
      'portal',
      '一网通办',
      Icons.apps_rounded,
      'https://eone.neuq.edu.cn/',
    ),
    CampusService.website(
      'campus-network',
      '校园网',
      Icons.wifi_rounded,
      'https://ipgate.neuq.edu.cn/',
    ),
    CampusService.inApp(
      'mail',
      '校园邮箱',
      Icons.mail_outline_rounded,
      '/services/mail',
    ),
    CampusService.website(
      'vpn',
      'WebVPN',
      Icons.vpn_lock_outlined,
      'https://vpn.neuq.edu.cn/',
    ),
  ],
  '就业': [
    CampusService.inApp(
      'employment',
      '宣讲会与招聘会',
      Icons.work_outline_rounded,
      '/services/employment',
    ),
  ],
};

final campusServices = {
  classroomsService.id: classroomsService,
  campusCardService.id: campusCardService,
  for (final service in campusServiceGroups.values.expand((entries) => entries))
    service.id: service,
};

const _legacyShortcutIds = ['academic', 'portal', 'mail', 'map'];

List<CampusService> shortcutsInOrder(
  List<String> saved, {
  required bool customized,
}) {
  final ids = customized
      ? saved.where(campusServices.containsKey).toSet()
      : {
          campusCardService.id,
          ...saved.where(_legacyShortcutIds.contains),
          ..._legacyShortcutIds,
        };
  return [for (final id in ids) campusServices[id]!];
}
