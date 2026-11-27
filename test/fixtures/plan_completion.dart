const planFixtureStudent = '00001234';

const planCompletionHtml =
    '''
<table class="infoTable">
  <tr><td class="title">学号:</td><td class="content">$planFixtureStudent</td>
    <td class="title">姓名:</td><td class="content">测试同学</td></tr>
  <tr><td class="title">学分:</td><td class="content">要求 12.5 / 完成 8.5</td>
    <td class="title">必修课学分:</td><td class="content">要求10/完成8.5</td>
    <td class="title">必修课门数:</td><td class="content">要求3门/完成2门</td>
    <td class="title">校内专用绩点:</td><td class="content">3.8125</td></tr>
</table>
<table class="formTable">
  <tr><td>课程</td><td>课程代码</td><td>课程名称</td><td>是否必修</td>
    <td>计划学分</td><td>完成学分</td><td>计划学期</td><td>成绩</td><td>通过否</td><td>备注</td></tr>
  <tr><td colspan="4">一&nbsp;通识类课程&nbsp;缺少选修课学分：1.5学分</td>
    <td>12.5</td><td>0</td><td></td><td></td><td>缺1.5分</td><td></td></tr>
  <tr><td colspan="4">(一)&nbsp;科学基础&nbsp;缺少选修课学分：1.5学分</td>
    <td>12.5</td><td>8.5</td><td></td><td></td><td>缺1.5分 缺1门</td><td></td></tr>
  <tr><td>1</td><td>TEST01</td><td>示例数学</td><td>是</td><td>4</td>
    <td>4</td><td>1-1</td><td>优秀</td><td>是</td><td>替代课程：示例基础</td></tr>
  <tr><td>2</td><td>TEST02</td><td>在读示例课程</td><td>是</td><td>4.5</td>
    <td>4.5</td><td>1-2</td><td>--</td><td>是</td><td>&nbsp;</td></tr>
  <tr><td>3</td><td>TEST03</td><td>未完成示例课程</td><td>是</td><td>1.5</td>
    <td>0</td><td>2-1</td><td>--</td><td>否</td><td></td></tr>
</table>
<table class="formTable">
  <tr><td colspan="9">计划外课程</td></tr>
  <tr><td>课程</td><td>课程代码</td><td>课程名称</td><td>是否必修</td>
    <td>计划学分</td><td>完成学分</td><td>成绩</td><td>通过否</td><td>备注</td></tr>
  <tr><td>1</td><td>EXTRA01</td><td>计划外示例课程</td><td>否</td>
    <td>1</td><td>1</td><td>合格</td><td>是</td><td>计划外</td></tr>
</table>
''';
