/// 平台默认头像：只有这一套，不做上传（`docs/truth/frontend/profile-settings.md`）。
/// key 与将来服务端 `account_info.avatar` 用同一套名字（issue #10），现在只落本机偏好。
const List<String> kHumanAvatars = <String>[
  'female_01',
  'female_02',
  'female_03',
  'male_01',
  'male_02',
  'male_03',
];

const List<String> kAgentAvatars = <String>['agent_blue', 'agent_pink', 'agent_gold'];

/// `type` 是 `account.type`：agent 只有三张，其余都按真人算。
List<String> avatarsFor(String type) => type == 'agent' ? kAgentAvatars : kHumanAvatars;

/// 本机偏好是信任边界：只认这套 key，别的一律当没选。
bool isKnownAvatar(String key) => kHumanAvatars.contains(key) || kAgentAvatars.contains(key);

String avatarAsset(String key) => 'assets/avatars/$key.png';
