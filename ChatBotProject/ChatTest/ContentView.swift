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
    
    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Text("EchoBot")
                        .font(.largeTitle)
                        .bold()
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Color.blue)
                }
                .padding()
                
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
            .navigationBarHidden(true)
        }
        .accentColor(colorScheme == .dark ? .white : .black)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            conversationStore.saveConversations()
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
                .padding(.top, 10)
                .padding(.leading, 16)
                
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
            .padding(.horizontal, 16)
            
            ScrollViewReader { proxy in
                ScrollView {
                    ForEach(conversation.messages.indices, id: \.self) { index in
                        let message = conversation.messages[index]
                        MessageView(message: message)
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
            .padding(.horizontal, 16)
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
