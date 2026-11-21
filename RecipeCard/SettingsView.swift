import StoreKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        PaperScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(spacing: 0) {
                        NavigationLink { BookListView(model: model) } label: {
                            SettingsLabel(key: "book.manage", symbol: "books.vertical")
                        }
                        .accessibilityIdentifier("manage-books")
                        Divider()
                        Button { model.backup() } label: {
                            SettingsLabel(key: "backup.create", symbol: "externaldrive")
                        }
                        .accessibilityIdentifier("backup-create")
                    }
                    .modifier(PaperCard())
                    VStack(spacing: 0) {
                        NavigationLink { PrivacyView() } label: {
                            SettingsLabel(key: "settings.privacy", symbol: "hand.raised")
                        }
                        .accessibilityIdentifier("settings-privacy")
                        Divider()
                        Button {
                            requestReview()
                        } label: {
                            SettingsLabel(key: "settings.rate", symbol: "star")
                        }
                        .accessibilityIdentifier("settings-review")
                    }
                    .modifier(PaperCard())
                    if !model.free {
                        VStack(spacing: 0) {
                            Button { model.panel = .paywall } label: {
                                SettingsLabel(key: model.entitlement?.purchasedPro == true ? "paywall.purchased" : "paywall.title",
                                              symbol: "sparkles")
                            }
                            .accessibilityIdentifier("settings-pro")
                            Divider()
                            Button { model.restorePurchases() } label: {
                                SettingsLabel(key: "paywall.restore", symbol: "arrow.clockwise")
                            }
                            .accessibilityIdentifier("settings-restore")
                        }
                        .modifier(PaperCard())
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                .padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L.t("common.close")) { model.panel = nil }.accessibilityIdentifier("settings-close")
            }
        }
    }
}

private struct SettingsLabel: View {
    let key: String
    let symbol: String
    var chevron = true

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).foregroundStyle(Paper.brand)
                .frame(width: 23).accessibilityHidden(true)
            Text(L.t(key)).font(.body.weight(.medium))
            Spacer()
            if chevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Paper.muted).accessibilityHidden(true)
            }
        }.padding(.horizontal, 15).padding(.vertical, 10)
            .frame(minHeight: 53).contentShape(Rectangle())
    }
}

struct BookListView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var editingID: UUID?
    @State private var name = ""

    var body: some View {
        PaperScreen {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(model.library.books) { book in
                        Button {
                            editingID = book.id
                            name = model.bookName(book)
                            editing = true
                        } label: {
                            HStack {
                                Text(model.bookName(book)).font(.body.weight(.semibold))
                                Spacer()
                                Image(systemName: "pencil").foregroundStyle(Paper.brand).accessibilityHidden(true)
                            }
                            .frame(minHeight: 49)
                            .padding(.horizontal, 14).modifier(PaperCard(radius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("rename-book-" + book.id.uuidString)
                    }
                    Button {
                        if model.hasPro {
                            editingID = nil
                            name = ""
                            editing = true
                        } else {
                            model.panel = .paywall
                        }
                    } label: { Label(L.t("book.add"), systemImage: "plus") }
                        .buttonStyle(PaperButton())
                        .accessibilityIdentifier("book-add")
                }
                .padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L.t("book.manage"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Label(L.t("common.back"), systemImage: "chevron.left")
                }
                .accessibilityIdentifier("books-back")
            }
        }
        .alert(L.t(editingID == nil ? "book.add" : "book.rename"), isPresented: $editing) {
            TextField(L.t("book.name"), text: $name)
            Button(L.t("common.cancel"), role: .cancel) {}
            Button(L.t("common.save")) {
                model.saveBook(id: editingID, name: name) { name = "" }
            }
        }
    }
}

private struct PrivacyView: View {
    var body: some View {
        PaperScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Paper.title(L.t("settings.privacy"))
                    Text(L.t("privacy.local"))
                    Text(L.t("privacy.sharing"))
                    Text(L.t("privacy.store"))
                }
                .frame(maxWidth: 620, alignment: .leading).padding(22).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L.t("settings.privacy"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PaywallView: View {
    @Bindable var model: AppModel

    var body: some View {
        PaperScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Paper.title(L.t("paywall.title"))
                    Text(L.t("paywall.intro")).font(.body).foregroundStyle(Paper.muted)
                    if model.expired {
                        Text(L.t("paywall.expired")).font(.subheadline).foregroundStyle(Paper.brand)
                    } else if let date = model.entitlement?.trialEnd, model.entitlement?.purchasedPro != true {
                        Text(L.f("paywall.until", date.formatted(date: .abbreviated, time: .omitted) as NSString))
                            .font(.subheadline.weight(.bold)).foregroundStyle(Paper.brand)
                    }
                    features
                    if model.entitlement?.purchasedPro == true {
                        Label(L.t("paywall.purchased"), systemImage: "checkmark.seal.fill")
                            .font(.headline).foregroundStyle(Paper.brand)
                    } else {
                        Button(buyText) { model.purchase(trial: false) }
                            .buttonStyle(PaperButton(tall: true)).accessibilityIdentifier("paywall-buy")
                        if !model.expired && model.entitlement?.trialClaimedAt == nil {
                            Button(L.t("paywall.claim")) { model.purchase(trial: true) }
                                .buttonStyle(PaperButton(primary: false)).accessibilityIdentifier("paywall-trial")
                        }
                    }
                    Button(L.t("paywall.restore")) { model.restorePurchases() }
                        .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("paywall-restore")
                    Text(L.t("paywall.footer")).font(.footnote).foregroundStyle(Paper.muted)
                }
                .disabled(model.busy)
                .padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L.t("common.close")) { model.panel = nil }.accessibilityIdentifier("paywall-close")
            }
        }
        .task { await model.loadProducts() }
    }

    private var buyText: String {
        if let price = model.product?.displayPrice ?? (model.testing ? "US$2.99" : nil) {
            return L.f("paywall.buyPrice", price as NSString)
        }
        return L.t("paywall.buy")
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L.t("paywall.books"), systemImage: "books.vertical")
            Label(L.t("paywall.scale"), systemImage: "person.2")
            Label(L.t("paywall.backup"), systemImage: "externaldrive")
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15).modifier(PaperCard())
    }
}
