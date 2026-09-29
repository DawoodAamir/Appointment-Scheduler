import SwiftUI

@main
struct AppointmentSchedulerApp: App {
    @StateObject private var store = ScheduleStore()
    var body: some Scene {
        WindowGroup { ScheduleView().environmentObject(store).tint(Color("AccentColor")) }
    }
}
struct ScheduleView: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.scenePhase) private var phase
    @State private var day = Date()
    @State private var editing: Appointment?
    @State private var query = ""
    @State private var showCancelled = false
    private var visible: [Appointment] {
        store.appointments.filter {
            Calendar.current.isDate($0.start, inSameDayAs: day)
                && (showCancelled || $0.status != .cancelled)
                && (query.isEmpty || $0.client.localizedCaseInsensitiveContains(query)
                    || $0.serviceName.localizedCaseInsensitiveContains(query))
        }.sorted { $0.start < $1.start }
    }
    var body: some View {
        NavigationView {
            List {
                Section {
                    DatePicker("Day", selection: $day, displayedComponents: .date)
                    HStack {
                        Label("\(visible.count) appointments", systemImage: "calendar")
                        Spacer()
                        Text(TimeZone.current.abbreviation() ?? "Local time").foregroundColor(
                            .secondary
                        ).font(.caption)
                    }
                }
                Section("Schedule") {
                    if visible.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nothing booked for this day.").font(.headline)
                            Text("Add an appointment or choose another date.").foregroundColor(
                                .secondary)
                        }.padding(.vertical, 10)
                    }
                    ForEach(visible) { item in
                        NavigationLink(destination: BookingDetail(id: item.id)) {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.start, style: .time).font(.headline).monospacedDigit()
                                    Text("\(item.durationMinutes) min").font(.caption)
                                        .foregroundColor(.secondary)
                                }.frame(minWidth: 70, alignment: .leading)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.client).font(.headline)
                                    Text(item.serviceName).font(.subheadline).foregroundColor(
                                        .secondary)
                                    Text(item.status.title).font(.caption.bold()).foregroundColor(
                                        item.status == .cancelled ? .secondary : .accentColor)
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                }
                Section {
                    Toggle("Show cancelled bookings", isOn: $showCancelled)
                    Button("Enable reminders") { Task { await store.enableReminders() } }
                    if let message = store.reminderMessage {
                        Text(message).font(.caption).foregroundColor(.secondary)
                    }
                } footer: {
                    Text(
                        "One calendar · weekdays, 9 AM–5 PM · times shown in your current time zone. Reminders are local to this device."
                    )
                }
            }.navigationTitle("Appointments")
                .searchable(text: $query, prompt: "Client or service")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            editing = Appointment(
                                start: BookingRules.availableSlots(
                                    on: day, minutes: 30, appointments: store.appointments
                                ).first ?? day)
                        } label: {
                            Image(systemName: "plus")
                        }.accessibilityLabel("New appointment")
                    }
                }
        }.navigationViewStyle(.stack)
            .sheet(item: $editing) { BookingEditor(appointment: $0) }
            .task { await store.reconcileReminders() }
            .onChange(of: phase) { if $0 == .active { Task { await store.reconcileReminders() } } }
            .alert(
                "Appointment",
                isPresented: Binding(
                    get: { store.error != nil }, set: { if !$0 { store.error = nil } })
            ) {
                Button("OK") { store.error = nil }
            } message: {
                Text(store.error ?? "")
            }
    }
}
struct BookingEditor: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @State var appointment: Appointment
    @State private var saveError: String?
    @State private var saving = false
    private var slots: [Date] {
        BookingRules.availableSlots(
            on: appointment.start, minutes: appointment.durationMinutes,
            appointments: store.appointments, excluding: appointment.id)
    }
    var body: some View {
        NavigationView {
            Form {
                Section("Client") {
                    TextField("Name", text: $appointment.client).textContentType(.name)
                    TextField("Contact details (optional)", text: $appointment.contact)
                }
                Section("Booking") {
                    Picker("Service", selection: $appointment.serviceID) {
                        ForEach(Service.catalog) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: appointment.serviceID) { id in
                        appointment.durationMinutes =
                            Service.catalog.first { $0.id == id }?.minutes ?? 30
                    }
                    DatePicker("Starts", selection: $appointment.start)
                    Stepper(
                        "\(appointment.durationMinutes) minutes",
                        value: $appointment.durationMinutes, in: 15...180, step: 15)
                    Picker("Status", selection: $appointment.status) {
                        ForEach(BookingStatus.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Remind me 15 minutes before", isOn: $appointment.reminder).disabled(
                        appointment.status == .cancelled)
                }
                Section("Available starts on this day") {
                    if slots.isEmpty {
                        Text("No available starts. Choose another date or a shorter duration.")
                            .foregroundColor(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], spacing: 8) {
                        ForEach(slots, id: \.self) { slot in
                            Button {
                                appointment.start = slot
                            } label: {
                                Text(slot, style: .time).font(.subheadline).frame(
                                    maxWidth: .infinity
                                ).padding(.vertical, 5)
                            }.buttonStyle(.bordered)
                        }
                    }
                }
                Section("Notes") {
                    TextEditor(text: $appointment.notes).frame(minHeight: 90).accessibilityLabel(
                        "Appointment notes")
                }
                if let saveError { Section { Text(saveError).foregroundColor(.red) } }
            }.navigationTitle("Booking details")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(saving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard store.save(appointment) else {
                                saveError = store.error
                                store.error = nil
                                return
                            }
                            saving = true
                            Task {
                                await store.reconcileReminders()
                                dismiss()
                            }
                        }.disabled(saving)
                    }
                }
        }.navigationViewStyle(.stack).interactiveDismissDisabled(saving)
    }
}
struct BookingDetail: View {
    let id: UUID
    @EnvironmentObject private var store: ScheduleStore
    @State private var editing: Appointment?
    @State private var exporting: ExportFile?
    @State private var confirmCancel = false
    var body: some View {
        Group {
            if let item = store.appointments.first(where: { $0.id == id }) {
                List {
                    Section {
                        Text(item.client).font(.title2.bold())
                        Text(item.serviceName).foregroundColor(.secondary)
                        Label(
                            item.status.title,
                            systemImage: item.status == .cancelled ? "xmark.circle" : "calendar")
                    }
                    Section("Time") {
                        Text(item.start.formatted(date: .complete, time: .shortened))
                        Text(
                            "\(item.durationMinutes) minutes · ends \(item.end.formatted(date: .omitted, time: .shortened))"
                        )
                        Text(TimeZone.current.identifier).font(.caption).foregroundColor(.secondary)
                    }
                    if !item.contact.isEmpty {
                        Section("Contact") { Text(item.contact).textSelection(.enabled) }
                    }
                    if !item.notes.isEmpty {
                        Section("Notes") { Text(item.notes).textSelection(.enabled) }
                    }
                    Section {
                        Button("Edit booking") { editing = item }
                        Button("Export calendar file") {
                            do { exporting = ExportFile(url: try store.export(item)) } catch {
                                store.error = error.localizedDescription
                            }
                        }
                        if item.status != .cancelled {
                            Button("Cancel appointment", role: .destructive) {
                                confirmCancel = true
                            }
                        }
                    } footer: {
                        Text(
                            "Calendar export creates a file to share or import. It does not send invitations or keep other calendars in sync."
                        )
                    }
                }.confirmationDialog(
                    "Cancel this appointment?", isPresented: $confirmCancel,
                    titleVisibility: .visible
                ) {
                    Button("Cancel appointment", role: .destructive) { store.cancel(item) }
                    Button("Keep booking", role: .cancel) {}
                }
            } else {
                Text("This booking is unavailable.")
            }
        }.navigationTitle("Appointment").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { BookingEditor(appointment: $0) }
            .sheet(item: $exporting) { ActivitySheet(items: [$0.url]) }
    }
}
struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
