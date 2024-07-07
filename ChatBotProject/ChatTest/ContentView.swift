import SwiftUI
import Alamofire
import os
import Firebase
import FirebaseRemoteConfig
import FirebaseFirestore
import StoreKit

// MARK: - Models

struct Message: Codable, Equatable, Identifiable {
    let id: UUID
    let role: String
    let content: String
    let timestamp: Date
    
    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

struct Conversation: Codable, Identifiable {
    var id: UUID
    var messages: [Message]
    var name: String {
        if let firstMessage = messages.first(where: { $0.role == "user" }) {
            return firstMessage.content
        } else {
            return "New Conversation"
        }
    }
    
    init(id: UUID = UUID(), messages: [Message]) {
        self.id = id
        self.messages = messages
    }
}

struct ChatCompletionResponse: Decodable {
    let choices: [ChatCompletionChoice]
}

struct ChatCompletionChoice: Decodable {
    let message: ChatCompletionMessage
}

struct ChatCompletionMessage: Decodable {
    let content: String
}

// MARK: - Managers

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var anyscaleUrl: String = "https://api.endpoints.anyscale.com/v1/chat/completions"
    @Published var maxMessageLength: Int = 1000
    @Published var freeMessageLimit: Int = 100
    @Published var anyscaleApiKey: String = "YOUR_DEFAULT_API_KEY"
    
    private init() {
        setupRemoteConfig()
    }
    
    private func setupRemoteConfig() {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 43200 // For development, set to 0. For production, set to a higher value.
        remoteConfig.configSettings = settings
        
        remoteConfig.setDefaults([
            "anyscale_url": self.anyscaleUrl as NSObject,
            "max_message_length": self.maxMessageLength as NSObject,
            "free_message_limit": self.freeMessageLimit as NSObject,
            "anyscale_api_key": self.anyscaleApiKey as NSObject
        ])
    }
    
    func fetchConfig() {
        RemoteConfig.remoteConfig().fetch { [weak self] (status, error) in
            if status == .success {
                RemoteConfig.remoteConfig().activate { [weak self] _, _ in
                    self?.updateConfigValues()
                }
            } else {
                print("Config fetch failed")
            }
        }
    }
    
    private func updateConfigValues() {
        let remoteConfig = RemoteConfig.remoteConfig()
        
        if let url = remoteConfig["anyscale_url"].stringValue {
            self.anyscaleUrl = url
        }
        
        if let length = remoteConfig["max_message_length"].numberValue as? Int {
            self.maxMessageLength = length
        }

        if let limit = remoteConfig["free_message_limit"].numberValue as? Int {
            self.freeMessageLimit = limit
        }
        
        if let apiKey = remoteConfig["anyscale_api_key"].stringValue {
            self.anyscaleApiKey = apiKey
        }
    }
}

class PurchaseManager: NSObject, ObservableObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    static let shared = PurchaseManager()
    
    @Published var hasActiveSubscription = false
    private var product: SKProduct?
    
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
        fetchProducts()
    }
    
    func fetchProducts() {
        let request = SKProductsRequest(productIdentifiers: Set(["com.yourapp.monthlysubscription"]))
        request.delegate = self
        request.start()
    }
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        if let product = response.products.first {
            self.product = product
        }
    }
    
    func purchaseSubscription() {
        guard let product = self.product else {
            print("Product not found")
            return
        }
        
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased, .restored:
                hasActiveSubscription = true
                SKPaymentQueue.default().finishTransaction(transaction)
            case .failed:
                print("Transaction failed: \(transaction.error?.localizedDescription ?? "")")
                SKPaymentQueue.default().finishTransaction(transaction)
            case .deferred, .purchasing:
                break
            @unknown default:
                break
            }
        }
    }
    
    func restorePurchases() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
}

class ConversationStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var totalMessageCount: Int = 0
    let userId: String
    
    private var db = Firestore.firestore()
    
    init() {
        if let storedUserId = UserDefaults.standard.string(forKey: "userId") {
            self.userId = storedUserId
        } else {
            let newUserId = UUID().uuidString
            UserDefaults.standard.set(newUserId, forKey: "userId")
            self.userId = newUserId
        }
        loadConversations()
    }
    
    func saveConversations() {
        let encoder = JSONEncoder()
        if let encodedData = try? encoder.encode(conversations) {
            UserDefaults.standard.set(encodedData, forKey: "conversations")
        }
        updateTotalMessageCount()
    }
    
    func loadConversations() {
        if let data = UserDefaults.standard.data(forKey: "conversations") {
            let decoder = JSONDecoder()
            if let decodedConversations = try? decoder.decode([Conversation].self, from: data) {
                conversations = decodedConversations
            }
        }
        updateTotalMessageCount()
    }
    
    private func updateTotalMessageCount() {
        totalMessageCount = conversations.reduce(0) { $0 + $1.messages.count }
    }
    
    func backupToFirebase(conversation: Conversation) {
        let conversationRef = db.collection("users").document(userId).collection("conversations").document(conversation.id.uuidString)
        
        conversationRef.getDocument { (document, error) in
            if let document = document, document.exists {
                // Update existing conversation
                conversationRef.updateData([
                    "messages": conversation.messages.map { [
                        "id": $0.id.uuidString,
                        "role": $0.role,
                        "content": $0.content,
                        "timestamp": Timestamp(date: $0.timestamp)
                    ] }
                ])
            } else {
                // Create new conversation
                conversationRef.setData([
                    "id": conversation.id.uuidString,
                    "messages": conversation.messages.map { [
                        "id": $0.id.uuidString,
                        "role": $0.role,
                        "content": $0.content,
                        "timestamp": Timestamp(date: $0.timestamp)
                    ] }
                ])
            }
        }
    }
}

// MARK: - Views

struct ConversationListView: View {
    @StateObject private var conversationStore = ConversationStore()
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var activeConversation: UUID?
    @State private var showDisclaimer: Bool = !UserDefaults.standard.bool(forKey: "DisclaimerAccepted")
    @State private var showingSupportView = false
    @State private var showingReferencesView = false
    @State private var showingPurchasePrompt = false

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Spacer()
                        Text("EchoBot")
                            .font(.largeTitle)
                            .bold()
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 26))
                            .foregroundColor(Color.blue)
                    Spacer()
                    Button(action: {
                        showingSupportView = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }
                    .sheet(isPresented: $showingSupportView) {
                        SupportView(showingSupportView: $showingSupportView, showingReferencesView: $showingReferencesView)
                    }
                }
                .padding()
                
                if showDisclaimer {
                    DisclaimerView(showDisclaimer: $showDisclaimer)
                } else {
                    mainContent
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .accentColor(colorScheme == .dark ? .white : .black)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            conversationStore.saveConversations()
        }
        .sheet(isPresented: $showingReferencesView) {
            ReferencesView(showingReferencesView: $showingReferencesView)
        }
        .alert(isPresented: $showingPurchasePrompt) {
            Alert(
                title: Text("Upgrade to Monthly Subscription"),
                message: Text("You've reached the free message limit for this month. Upgrade to continue chatting."),
                primaryButton: .default(Text("Subscribe for $10/month"), action: purchaseManager.purchaseSubscription),
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            configManager.fetchConfig()
            checkAndPromptForSubscription()
        }
    }
    
    var mainContent: some View {
        Group {
            if conversationStore.conversations.isEmpty {
                Text("Welcome to EchoBot! Start a new conversation.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                List {
                    ForEach(conversationStore.conversations.indices, id: \.self) { index in
                        NavigationLink(
                            destination: ChatView(conversation: $conversationStore.conversations[index], onEmptyConversation: {
                                deleteEmptyConversation(at: index)
                            }, conversationStore: conversationStore),
                            tag: conversationStore.conversations[index].id,
                            selection: $activeConversation
                        ) {
                            Text(conversationStore.conversations[index].name)
                        }
                    }
                    .onDelete(perform: deleteConversation)
                }
                .listStyle(PlainListStyle())
            }
            
            Button(action: startNewConversation) {
                Text("Start a new conversation")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding()
        }
    }
    
    func startNewConversation() {
        let newConversation = Conversation(messages: [Message(role: "assistant", content: "Hello! How can I assist you today?")])
        conversationStore.conversations.append(newConversation)
        activeConversation = newConversation.id
        conversationStore.saveConversations()
    }
    
    func deleteEmptyConversation(at index: Int) {
        if conversationStore.conversations[index].messages.isEmpty {
            conversationStore.conversations.remove(at: index)
            conversationStore.saveConversations()
        }
    }
    
    func deleteConversation(at offsets: IndexSet) {
        conversationStore.conversations.remove(atOffsets: offsets)
        conversationStore.saveConversations()
    }
    
    func checkAndPromptForSubscription() {
        if conversationStore.totalMessageCount >= configManager.freeMessageLimit && !purchaseManager.hasActiveSubscription {
            showingPurchasePrompt = true
        }
    }
}

struct DisclaimerView: View {
    @Binding var showDisclaimer: Bool
    
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Spacer()
            Text("By using this app, you acknowledge that I am an AI chatbot, not a licensed healthcare professional. I provide support based on general knowledge and do not replace professional advice. Use this information responsibly and at your own risk.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .gray.opacity(0.4), radius: 3, x: 2, y: 2)
                .padding(.horizontal, 20)
            
            Button("Accept") {
                UserDefaults.standard.set(true, forKey: "DisclaimerAccepted")
                showDisclaimer = false
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(width: 280, height: 44)
            .background(Color.green)
            .cornerRadius(22)
            .shadow(radius: 3)
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.edgesIgnoringSafeArea(.all))
    }
}

struct SupportView: View {
    @Binding var showingSupportView: Bool
    @Binding var showingReferencesView: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Support")
                    .font(.largeTitle)
                    .bold()
                    .padding()
                
                Text("If you have any questions or need assistance, please contact our support team at echobot583@gmail.com ")
                    .font(.body)
                    .padding()
                
                Button(action: {
                    showingSupportView = false
                    showingReferencesView = true
                }) {
                    Text("View References")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
                
                Spacer()
            }
            .navigationBarItems(trailing: Button("Close") {
                showingSupportView = false
            })
        }
    }
}

struct ReferencesView: View {
    @Binding var showingReferencesView: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                Text("References")
                    .font(.largeTitle)
                    .bold()
                    .padding()
                
                Text("EchoBot's responses are generated based on patterns and information found in a diverse range of online sources. These sources are not curated for medical reliability and should not be considered a replacement for professional medical advice. For references go to http://echobotapp.com/support")
                    .font(.body)
                    .padding()
                    Spacer()
                                }
                                .navigationBarItems(trailing: Button("Close") {
                                    showingReferencesView = false
                                })
                            }
                        }
                    }

    struct ChatView: View {
        @Binding var conversation: Conversation
        var onEmptyConversation: () -> Void
        @State private var messageText = ""
        @Environment(\.colorScheme) var colorScheme
        @Environment(\.presentationMode) var presentationMode
        var conversationStore: ConversationStore
        @StateObject private var configManager = ConfigManager.shared
        @StateObject private var purchaseManager = PurchaseManager.shared
        @State private var showingPurchasePrompt = false
        
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                .padding(.top, 5)
                .padding(.leading, 10)
                                
                Spacer()
                
                HStack {
                    Text("EchoBot")
                        .font(.largeTitle)
                        .bold()
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Color.blue)
                }
                
                Spacer()
            }
            .padding(.horizontal, 10)
            
            ScrollViewReader { proxy in
                ScrollView {
                    ForEach(conversation.messages) { message in
                        MessageView(message: message)
                            .id(message.id)
                    }
                }
                .onChange(of: conversation.messages) { _ in
                    withAnimation {
                        proxy.scrollTo(conversation.messages.last?.id, anchor: .bottom)
                    }
                }
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            
            HStack {
                TextField("Type something", text: $messageText)
                    .padding(8)
                    .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(10)
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.blue)
                .cornerRadius(8)
                .font(.system(size: 20))
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .navigationBarHidden(true)
        .onDisappear {
            if conversation.messages.isEmpty {
                onEmptyConversation()
            }
            conversationStore.saveConversations()
        }
        .alert(isPresented: $showingPurchasePrompt) {
            Alert(
                title: Text("Upgrade to Monthly Subscription"),
                message: Text("You've reached the free message limit for this month. Upgrade to continue chatting."),
                primaryButton: .default(Text("Subscribe for $10/month"), action: purchaseManager.purchaseSubscription),
                secondaryButton: .cancel()
            )
        }
    }
        
    func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        if conversationStore.totalMessageCount >= configManager.freeMessageLimit && !purchaseManager.hasActiveSubscription {
            showingPurchasePrompt = true
            return
        }
        
        let newMessage = Message(role: "user", content: trimmedMessage)
        conversation.messages.append(newMessage)
        messageText = ""
        
        sendMessageToAnyscale(message: newMessage)
        
        if conversation.messages.count % 5 == 0 {
            conversationStore.backupToFirebase(conversation: conversation)
        }
        
        conversationStore.saveConversations()
    }
        
    func sendMessageToAnyscale(message: Message) {
        let maxTokens = configManager.maxMessageLength
        
        var jsonMessages: [[String: String]] = []
        var totalTokens = 0
        
        for message in conversation.messages.reversed() {
            let messageTokens = estimateTokenCount(message.content)
            if totalTokens + messageTokens > maxTokens {
                break
            }
            jsonMessages.insert(["role": message.role, "content": message.content], at: 0)
            totalTokens += messageTokens
        }
        
        let parameters: [String: Any] = [
            "model": "mistralai/Mixtral-8x7B-Instruct-v0.1:akshit:UBXmwGF",
            "messages": jsonMessages,
            "temperature": 0.7
        ]
        
        let headers: HTTPHeaders = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(configManager.anyscaleApiKey)"
        ]
        
        AF.request(configManager.anyscaleUrl, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
            .responseDecodable(of: ChatCompletionResponse.self) { response in
                switch response.result {
                case .success(let chatCompletionResponse):
                    if let content = chatCompletionResponse.choices.first?.message.content {
                        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        let assistantMessage = Message(role: "assistant", content: trimmedContent)
                        DispatchQueue.main.async {
                            self.conversation.messages.append(assistantMessage)
                            self.conversationStore.saveConversations()
                            
                            if self.conversation.messages.count % 5 == 0 {
                                self.conversationStore.backupToFirebase(conversation: self.conversation)
                            }
                        }
                    }
                case .failure(let error):
                    print("Network error: \(error.localizedDescription)")
                    let errorMessage = Message(role: "assistant", content: "Sorry, something went wrong. Please try again.")
                    DispatchQueue.main.async {
                        self.conversation.messages.append(errorMessage)
                        self.conversationStore.saveConversations()
                    }
                }
            }
    }
        
    func estimateTokenCount(_ text: String) -> Int {
        return text.split(separator: " ").count * 4 / 3
    }
}

    struct MessageView: View {
        let message: Message
        
        var body: some View {
            HStack {
                if message.role == "user" {
                    Spacer()
                    Text(message.content)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(ChatBubble(isFromCurrentUser: true))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                } else {
                    Text(message.content)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .clipShape(ChatBubble(isFromCurrentUser: false))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    Spacer()
                }
            }
        }
    }

    struct ChatBubble: Shape {
        var isFromCurrentUser: Bool
        
        func path(in rect: CGRect) -> Path {
            let path = UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight, isFromCurrentUser ? .bottomLeft : .bottomRight], cornerRadii: CGSize(width: 16, height: 16))
            return Path(path.cgPath)
        }
    }

                @main
                struct ChatApp: App {
                    @StateObject private var conversationStore = ConversationStore()
                    
                    init() {
                        setupFirebase()
                    }
                    
                    var body: some Scene {
                        WindowGroup {
                            ConversationListView()
                                .environmentObject(conversationStore)
                        }
                    }
                    
                    private func setupFirebase() {
                        FirebaseApp.configure()
                    }
                }
                
