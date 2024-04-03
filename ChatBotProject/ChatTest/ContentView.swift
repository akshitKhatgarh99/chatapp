import SwiftUI
import Alamofire

struct Message: Codable, Equatable {
    let role: String
    let content: String
}

struct Conversation: Identifiable {
    let id = UUID()
    var messages: [Message]
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

struct ConversationListView: View {
    @State private var conversations: [Conversation] = []
    @State private var selectedConversationIndex: Int?
    @Environment(\.colorScheme) var colorScheme
    
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
                
                if conversations.isEmpty {
                    Text("Welcome to EchoBot! Start a new conversation.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        ForEach(conversations.indices, id: \.self) { index in
                            NavigationLink(
                                destination: ChatView(conversation: $conversations[index]),
                                tag: index,
                                selection: $selectedConversationIndex
                            ) {
                                Text("Conversation \(index + 1)")
                            }
                        }
                        .onDelete(perform: deleteConversation)
                    }
                    .listStyle(PlainListStyle())
                }
                
                Button(action: {
                    startNewConversation()
                }) {
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
    }
    
    func startNewConversation() {
        let newConversation = Conversation(messages: [])
        conversations.append(newConversation)
        selectedConversationIndex = conversations.count - 1
    }
    
    func deleteConversation(at offsets: IndexSet) {
        conversations.remove(atOffsets: offsets)
    }
}

struct ChatView: View {
    @Binding var conversation: Conversation
    @State private var messageText = ""
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
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
                .padding()
                
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
            .padding()
            
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
                    .padding()
                    .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(20)
                    .onSubmit {
                        sendMessage(message: messageText)
                    }
                
                Button {
                    sendMessage(message: messageText)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                }
                .font(.system(size: 24))
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding()
        }
        .navigationBarHidden(true)
    }
    
    func sendMessage(message: String) {
        withAnimation {
            conversation.messages.append(Message(role: "user", content: message))
            self.messageText = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    sendMessageToServer(message: message) { response in
                        conversation.messages.append(Message(role: "assistant", content: response))
                    }
                }
            }
        }
    }
    
    
    func sendMessageToServer(message: String, completion: @escaping (String) -> Void) {
        let jsonMessages = conversation.messages.suffix(20).map { message -> [String: String] in
            return ["role": message.role, "content": message.content]
        }
        
        let parameters: [String: Any] = [
            "model": "meta-llama/Llama-2-70b-chat-hf",
            "messages": jsonMessages + [["role": "user", "content": message]],
            "temperature": 0.7
        ]
        
        let url = "https://api.endpoints.anyscale.com/v1/chat/completions" // Replace with the actual API base URL
        
        let headers: HTTPHeaders = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(openaiApiKey)"
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
                    print("Error: \(error)")
                    completion("Sorry, something went wrong.")
                }
            }
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
