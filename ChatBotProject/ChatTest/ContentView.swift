import SwiftUI
import Alamofire
import os

struct Message: Codable, Equatable {
    let role: String
    let content: String
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

class ConversationStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    
    init() {
        loadConversations()
    }
    
    func saveConversations() {
        let encoder = JSONEncoder()
        if let encodedData = try? encoder.encode(conversations) {
            UserDefaults.standard.set(encodedData, forKey: "conversations")
        }
    }
    
    func loadConversations() {
        if let data = UserDefaults.standard.data(forKey: "conversations") {
            let decoder = JSONDecoder()
            if let decodedConversations = try? decoder.decode([Conversation].self, from: data) {
                conversations = decodedConversations
            }
        }
    }
}

struct ConversationListView: View {
    @StateObject private var conversationStore = ConversationStore()
    @Environment(\.colorScheme) var colorScheme
    @State private var activeConversation: UUID?
    @State private var showDisclaimer: Bool = !UserDefaults.standard.bool(forKey: "DisclaimerAccepted")
    @State private var showingSupportView = false
    @State private var showingReferencesView = false

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
            
//            Text("Please note that EchoBot is an AI chatbot based on general knowledge and does not have access to specific medical references or sources. The information provided by EchoBot should not be considered as a substitute for professional medical advice, diagnosis, or treatment.")
//                .font(.system(size: 14, weight: .medium, design: .rounded))
//                .foregroundColor(.gray)
//                .multilineTextAlignment(.center)
//                .padding()
//            
//            Text("Always consult with a qualified healthcare professional for personalized medical advice and guidance.")
//                .font(.system(size: 14, weight: .medium, design: .rounded))
//                .foregroundColor(.gray)
//                .multilineTextAlignment(.center)
//                .padding()
            
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
    let openaiApiKey = "esecret_ctyfftvnkwxucq3ftfhmqax14s" // Replace with your actual API key
    
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
                    ForEach(conversation.messages.indices, id: \.self) { index in
                        MessageView(message: conversation.messages[index])
                            .id(index)
                    }
                }
                .onChange(of: conversation.messages) { _ in
                    withAnimation {
                        proxy.scrollTo(conversation.messages.count - 1, anchor: .bottom)
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
                    sendMessage(message: messageText)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.blue)
                .cornerRadius(8)
                .font(.system(size: 20))
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
    }
    
    func sendMessage(message: String) {
        withAnimation {
            conversation.messages.append(Message(role: "user", content: message))
            self.messageText = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    sendMessageToServer(message: message) { response in
                        conversation.messages.append(Message(role: "assistant", content: response))
                        conversationStore.saveConversations()
                    }
                }
            }
        }
    }
    
    func sendMessageToServer(message: String, completion: @escaping (String) -> Void) {
        let maxWords = 500

        // Debugging: Print current conversation messages
        print("Current messages: \(conversation.messages.map { $0.content })")

        // Take the last 20 messages from the conversation
        var jsonMessages = conversation.messages.suffix(20).map { message -> [String: String] in
            return ["role": message.role, "content": message.content]
        }
        
        // Calculate the total word count of these messages
        var totalWords = jsonMessages.reduce(0) { $0 + $1["content"]!.split(separator: " ").count }
        
        // Check and add new message only if it's not the last message already present
        if jsonMessages.last?["content"] != message {
            let newMessageWordCount = message.split(separator: " ").count
            while totalWords + newMessageWordCount > maxWords {
                jsonMessages.removeFirst()
                totalWords = jsonMessages.reduce(0) { $0 + $1["content"]!.split(separator: " ").count }
            }
            // Append the new user message
            jsonMessages.append(["role": "user", "content": message])
        }
        
        let parameters: [String: Any] = [
            "model": "mistralai/Mixtral-8x7B-Instruct-v0.1:akshit:UBXmwGF",
            "messages": jsonMessages,
            "temperature": 0.7
        ]
        
        let url = "https://echobotapp.com:8080/chat" // Adjust as necessary
        let headers: HTTPHeaders = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(openaiApiKey)",
            "User-Identifier": getUniqueIdentifier() // Add the user identifier header
        ]
        
        AF.request(url, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
            .responseDecodable(of: ChatCompletionResponse.self) { response in
                switch response.result {
                case .success(let chatCompletionResponse):
                    if let content = chatCompletionResponse.choices.first?.message.content {
                        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        completion(trimmedContent)
                    } else {
                        completion("Sorry, no response received from the API.")
                    }
                case .failure(let error):
                    os_log("Network error: %s", log: OSLog.default, type: .error, error.localizedDescription)
                    completion("Sorry, something went wrong.")
                }
            }
    }
    
    func getUniqueIdentifier() -> String {
            // Check if the identifier is already saved in UserDefaults
            if let storedIdentifier = UserDefaults.standard.string(forKey: "uniqueIdentifier") {
                return storedIdentifier
            }
            
            // Generate a new UUID and store it
            let newIdentifier = UUID().uuidString
            UserDefaults.standard.set(newIdentifier, forKey: "uniqueIdentifier")
            return newIdentifier
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
            .animation(.default, value: message)
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
    struct ChatTestApp: App {
        @StateObject private var conversationStore = ConversationStore()
        
        var body: some Scene {
            WindowGroup {
                ContentView()
                    .environmentObject(conversationStore)
            }
        }
    }

    struct ContentView: View {
        var body: some View {
            ConversationListView()
        }
    }

    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
