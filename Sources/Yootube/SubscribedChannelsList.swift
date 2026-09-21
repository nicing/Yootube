import SwiftUI

struct SubscribedChannelsList: View {
    @ObservedObject var subscriptions: ChannelSubscriptionStore
    let available: Bool
    let open: (ChannelSubscription) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 18, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L10n.t("订阅的频道")).font(.system(size: 15, weight: .semibold))
                Spacer()
                if !subscriptions.channels.isEmpty {
                    Text(L10n.t("\(subscriptions.channels.count) 个频道"))
                        .font(.caption).foregroundStyle(KumoTheme.subtle)
                }
            }
            if !subscriptions.isLoaded {
                HStack {
                    Text(L10n.t("本地订阅暂时无法读取")).foregroundStyle(KumoTheme.subtle)
                    Button(L10n.t("重新读取")) { subscriptions.reload() }
                }
                .frame(maxWidth: .infinity, minHeight: 88)
            } else if subscriptions.channels.isEmpty {
                HStack(spacing: 12) {
                    KumoIcon("bell", size: 19)
                    Text(L10n.t("订阅频道后会显示在这里")).font(.callout)
                }
                .foregroundStyle(KumoTheme.subtle)
                .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(subscriptions.channels) { channel in
                        SubscriptionChannelCard(channel: channel, available: available) {
                            open(channel)
                        }
                    }
                }
            }
        }
    }
}

private struct SubscriptionChannelCard: View {
    let channel: ChannelSubscription
    let available: Bool
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 10) {
                NativeRemoteImage(url: available ? channel.avatarURL : nil, icon: "user")
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                Text(channel.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KumoTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
            }
            .padding(10)
            .background(hovered ? KumoTheme.tint.opacity(0.7) : .clear,
                        in: RoundedRectangle(cornerRadius: KumoTheme.radiusPanel))
            .contentShape(RoundedRectangle(cornerRadius: KumoTheme.radiusPanel))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(channel.name)
        .accessibilityLabel(L10n.t("打开频道 \(channel.name)"))
    }
}
