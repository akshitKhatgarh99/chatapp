import SwiftUI
import Alamofire

struct Message: Codable, Equatable {
    let role: String
    let content: String
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

struct ContentView: View {
    @State private var messageText = ""
    @State var messages: [Message] = []
    let openaiApiKey = "esecret_ctyfftvnkwxucq3ftfhmqax14s" // Replace with your actual API key
    
    var body: some View {
        VStack {
            HStack {
                Text("EchoBot")
                    .font(.largeTitle)
                    .bold()
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Color.blue)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    ForEach(messages.indices, id: \.self) { index in
                        let message = messages[index]
                        MessageView(message: message)
                            .id(index)
                    }
                }
                .onChange(of: messages) { _ in
                    withAnimation {
                        proxy.scrollTo(messages.count - 1, anchor: .bottom)
                    }
                }
            }
            .background(Color.gray.opacity(0.1))
            
            HStack {
                TextField("Type something", text: $messageText)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(20)
                    .onSubmit {
                        sendMessage(message: messageText)
                    }
                Button {
                    sendMessage(message: messageText)
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .font(.system(size: 26))
                .padding(.horizontal, 10)
            }
            .padding()
        }
    }
    
    func sendMessage(message: String) {
        withAnimation {
            messages.append(Message(role: "user", content: message))
            self.messageText = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    sendMessageToServer(message: message) { response in
                        messages.append(Message(role: "assistant", content: response))
                    }
                }
            }
        }
    }
    
    func sendMessageToServer(message: String, completion: @escaping (String) -> Void) {
        let jsonMessages = messages.suffix(20).map { message -> [String: String] in
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
