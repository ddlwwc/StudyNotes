import SwiftUI

@MainActor
public struct SnapshotWorkspaceView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            WorkspaceSnapshotHeader()
            HStack(spacing: 0) {
                SnapshotSidebar()
                    .frame(width: SNMetric.sidebarWidth)

                SnapshotMaterialList()
                    .frame(width: SNMetric.materialListWidth)

                SnapshotReader()
                    .frame(minWidth: 460, maxWidth: .infinity)

                SnapshotStudyPanel()
                    .frame(width: SNMetric.studyPanelWidth)
            }
        }
        .frame(width: 1_440, height: 1_024)
        .background(SNColor.white)
        .preferredColorScheme(.light)
    }
}

#Preview("知识库工作台") {
    SnapshotWorkspaceView()
}

private struct SnapshotSidebar: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("知识库")
                    .font(.sn(18, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SNColor.text)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 2) {
                Text("开始")
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(SNColor.muted)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                SnapshotSidebarRow(
                    title: "全部材料",
                    systemImage: "tray.full",
                    count: "1",
                    isSelected: true
                )
                SnapshotSidebarRow(
                    title: "收件箱",
                    systemImage: "inbox",
                    detail: "即将推出"
                )

                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                HStack {
                    Text("我的知识库")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.muted)
                    Spacer()
                    Text("1")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                SnapshotSidebarRow(
                    title: "学习科学",
                    systemImage: "books.vertical",
                    count: "1"
                )
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(SNColor.green)
                        .frame(width: 6, height: 6)
                    Text("iCloud 目录 · 已连接")
                        .font(.sn(10, weight: .medium))
                        .foregroundStyle(SNColor.text)
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(SNColor.muted)
                }
                Text("StudyNotes")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(SNColor.white)
            .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: SNRadius.control)
                    .stroke(SNColor.border, lineWidth: 1)
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .background(SNColor.nav)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SNColor.border)
                .frame(width: 1)
        }
    }
}

private struct SnapshotSidebarRow: View {
    let title: String
    let systemImage: String
    var count: String?
    var detail: String?
    var isSelected = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
                .frame(width: 16)
            Text(title)
                .font(.sn(12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? SNColor.blue : SNColor.text)
                .lineLimit(1)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
            } else if let count {
                Text(count)
                    .font(.sn(10))
                    .foregroundStyle(SNColor.muted)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(isSelected ? SNColor.blueSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: SNRadius.small))
    }
}

private struct SnapshotMaterialList: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("学习科学")
                        .font(.sn(15, weight: .semibold))
                        .foregroundStyle(SNColor.ink)
                    Spacer()
                }
                Text("知识库 / 1 个分类")
                    .font(.sn(10))
                    .foregroundStyle(SNColor.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(SNColor.muted)
                Text("搜索当前材料")
                    .font(.sn(11))
                    .foregroundStyle(SNColor.muted)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(SNColor.nav)
            .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: SNRadius.control)
                    .stroke(SNColor.border, lineWidth: 1)
            }
            .padding(.horizontal, 12)

            HStack {
                Text("全部 1")
                    .font(.sn(11, weight: .medium))
                    .foregroundStyle(SNColor.blue)
                Spacer()
                Text("最近更新")
                    .font(.sn(10))
                    .foregroundStyle(SNColor.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            SnapshotMaterialRow()

            Spacer()
        }
        .background(SNColor.white)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SNColor.border)
                .frame(width: 1)
        }
    }
}

private struct SnapshotMaterialRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(SNColor.white)
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SNColor.blue)
            }
            .frame(width: 24, height: 24)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(SNColor.blueLine, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("认知负荷理论与学习设计")
                    .font(.sn(12, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                    .lineLimit(2)
                Text("Markdown 笔记 · 今天 10:42")
                    .font(.sn(9))
                    .foregroundStyle(SNColor.muted)
            }

            Spacer(minLength: 4)
        }
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(SNColor.blueSoft)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(SNColor.blue)
                .frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)
                .padding(.leading, 16)
        }
    }
}

private struct SnapshotReader: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 12))
                    .foregroundStyle(SNColor.muted)
                Text("学习科学 / 认知负荷理论与学习设计")
                    .font(.sn(11))
                    .foregroundStyle(SNColor.text)
                    .lineLimit(1)
                Spacer()
                SnapshotReaderTool(title: "目录", systemImage: "list.bullet.rectangle")
                SnapshotReaderTool(title: "搜索", systemImage: "magnifyingglass")
                SnapshotReaderTool(title: "编辑副本", systemImage: "square.and.pencil")
                Rectangle()
                    .fill(SNColor.border)
                    .frame(width: 1, height: 20)
                SnapshotReaderTool(title: "收起研读层", systemImage: "sidebar.right")
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("认知负荷理论与学习设计")
                    .font(.sn(30, weight: .semibold))
                    .foregroundStyle(SNColor.ink)

                HStack(spacing: 6) {
                    Text("Markdown 笔记")
                    Text("·")
                    Text("更新于 今天 10:42")
                    Text("·")
                    Text("学习科学")
                }
                .font(.sn(11))
                .foregroundStyle(SNColor.muted)
                .padding(.top, 8)

                Rectangle()
                    .fill(SNColor.border)
                    .frame(height: 1)
                    .padding(.vertical, 22)

                MarkdownRenderer(markdown: SampleSnapshotContent.markdown, blockSpacing: 14)
            }
            .frame(maxWidth: 648, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)
        }
        .background(SNColor.white)
    }
}

private struct SnapshotReaderTool: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
            Text(title)
                .font(.sn(10))
        }
        .foregroundStyle(SNColor.muted.opacity(0.72))
        .padding(.horizontal, 6)
        .frame(height: 28)
    }
}

private struct SnapshotStudyPanel: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("研读层")
                    .font(.sn(15, weight: .semibold))
                    .foregroundStyle(SNColor.ink)
                Spacer()
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13))
                    .foregroundStyle(SNColor.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            HStack(spacing: 18) {
                VStack(spacing: 7) {
                    Text("标注")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.ink)
                    Rectangle()
                        .fill(SNColor.blue)
                        .frame(height: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                }
                .frame(minWidth: 42)

                VStack(spacing: 7) {
                    Text("AI 研读")
                        .font(.sn(11))
                        .foregroundStyle(SNColor.muted)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2)
                }
                .frame(minWidth: 42)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Rectangle()
                .fill(SNColor.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("03")
                            .font(.sn(11, weight: .medium))
                            .foregroundStyle(Color(red: 0.55, green: 0.33, blue: 0.0))
                        Spacer()
                    }

                    Text("“有效设计应降低无关负荷，并为生成性加工留出空间。”")
                        .font(.snReading(12))
                        .foregroundStyle(SNColor.text)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("关键不只是减少内容，而是让注意力进入关系建构。")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .background(Color(red: 1.0, green: 0.984, blue: 0.937))
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .stroke(SNColor.yellowLine, lineWidth: 1)
                }

                VStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(SNColor.muted)
                    Text("标注数据层尚未接入")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.text)
                    Text("当前构建不会读取或伪造持久化标注。")
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text("向 AI 提问当前选段")
                        .font(.sn(11, weight: .medium))
                        .foregroundStyle(SNColor.ink)
                    Text("AI 研读尚未配置，不会发送内容。")
                        .font(.sn(9))
                        .foregroundStyle(SNColor.muted)
                    Text("解释这段内容与外在负荷的关系")
                        .font(.sn(10))
                        .foregroundStyle(SNColor.muted)
                        .padding(9)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                        .background(SNColor.white)
                        .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: SNRadius.control)
                                .stroke(SNColor.border, lineWidth: 1)
                        }
                }
                .padding(12)
                .background(SNColor.white)
                .clipShape(RoundedRectangle(cornerRadius: SNRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: SNRadius.control)
                        .stroke(SNColor.border, lineWidth: 1)
                }
            }
            .padding(14)

            Spacer(minLength: 0)
        }
        .background(SNColor.panel)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(SNColor.border)
                .frame(width: 1)
        }
    }
}

private enum SampleSnapshotContent {
    static let markdown = """
    认知负荷理论关注工作记忆在学习过程中的限制。教学设计的目标并不是一味减少信息，而是把有限的学习资源引向与图式建构相关的活动。

    ## 三种认知负荷

    - **内在负荷**：来自材料本身的复杂性。
    - **外在负荷**：由不恰当的呈现方式产生。
    - **生成性负荷**：用于图式建构和迁移。

    > 有效设计应降低无关负荷，并为生成性加工留出空间。

    因此，图文整合、分段呈现与及时反馈需要共同服务于概念之间的关系，而不是停留在视觉层面的整齐。

    理解这三种负荷的作用机制，有助于在教学设计中做出合理取舍。关键不是简单地追求“更少的内容”，而是通过适合的呈现与活动设计，让有限的认知资源更多地服务于知识的深入理解和灵活应用。

    ## 本节要点

    1. 三种负荷共同影响学习者的认知资源分配。
    2. 降低无关负荷并不等于删掉所有复杂内容。

    ## 进一步核对

    1. 当前的图文结构是否把注意力引向概念关系？
    2. 装饰性信息是否挤占了生成性加工的空间？
    3. 分段、反馈与练习是否服务于同一学习目标？
    """
}
