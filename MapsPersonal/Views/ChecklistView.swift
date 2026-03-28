import SwiftUI

// MARK: - Checklist List View

struct ChecklistListView: View {
    @State private var store = ChecklistStore()
    @State private var showNewList = false
    @State private var newListName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.checklists) { checklist in
                    NavigationLink {
                        ChecklistDetailView(store: store, checklistId: checklist.id)
                    } label: {
                        HStack {
                            Text(checklist.name)
                            Spacer()
                            if !checklist.items.isEmpty {
                                Text(checklist.progress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    store.deleteChecklist(at: offsets)
                }
            }
            .overlay {
                if store.checklists.isEmpty {
                    ContentUnavailableView("No Checklists",
                        systemImage: "checklist",
                        description: Text("Tap + to create one"))
                }
            }
            .navigationTitle("Checklists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewList = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Checklist", isPresented: $showNewList) {
                TextField("Name", text: $newListName)
                Button("Cancel", role: .cancel) { newListName = "" }
                Button("Create") {
                    let name = newListName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        store.addChecklist(name: name)
                    }
                    newListName = ""
                }
            }
        }
    }
}

// MARK: - Checklist Detail View

struct ChecklistDetailView: View {
    let store: ChecklistStore
    let checklistId: UUID
    @State private var newItemText = ""
    @FocusState private var isAddingItem: Bool

    private var checklist: Checklist? {
        store.checklists.first { $0.id == checklistId }
    }

    var body: some View {
        if let checklist {
            List {
                // Items
                ForEach(checklist.items) { item in
                    Button {
                        store.toggleItem(checklistId: checklistId, itemId: item.id)
                    } label: {
                        HStack {
                            Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isChecked ? .green : .secondary)
                            Text(item.text)
                                .strikethrough(item.isChecked)
                                .foregroundStyle(item.isChecked ? .secondary : .primary)
                        }
                    }
                }
                .onDelete { offsets in
                    store.deleteItem(checklistId: checklistId, at: offsets)
                }

                // Add new item
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                    TextField("Add item", text: $newItemText)
                        .focused($isAddingItem)
                        .onSubmit {
                            addItem()
                        }
                }
            }
            .navigationTitle(checklist.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            store.uncheckAll(checklistId: checklistId)
                        } label: {
                            Label("Uncheck All", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private func addItem() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            store.addItem(to: checklistId, text: text)
            newItemText = ""
            isAddingItem = true
        }
    }
}
