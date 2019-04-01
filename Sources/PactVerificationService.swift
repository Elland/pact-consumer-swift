import Alamofire
import BrightFutures
import Foundation

open class PactVerificationService {
    open var baseUrl: String {
        return Router.baseURLString
    }

    enum Router: URLRequestConvertible {
        static var baseURLString = "http://example.com"

        case clean
        case setup([String: Any])
        case verify
        case write([String: [String: String]])

        var method: HTTPMethod {
            switch self {
            case .clean:
                return .delete
            case .setup:
                return .put
            case .verify:
                return .get
            case .write:
                return .post
            }
        }

        var path: String {
            switch self {
            case .clean:
                return "/interactions"
            case .setup:
                return "/interactions"
            case .verify:
                return "/interactions/verification"
            case .write:
                return "/pact"
            }
        }

        // MARK: URLRequestConvertible

        func asURLRequest() throws -> URLRequest {
            let url = try Router.baseURLString.asURL()
            var urlRequest = URLRequest(url: url.appendingPathComponent(path))
            urlRequest.httpMethod = method.rawValue
            urlRequest.setValue("true", forHTTPHeaderField: "X-Pact-Mock-Service")

            switch self {
            case let .setup(parameters):
                return try JSONEncoding.default.encode(urlRequest, with: parameters)
            case let .write(parameters):
                return try JSONEncoding.default.encode(urlRequest, with: parameters)
            default:
                return urlRequest
            }
        }
    }

    public init(url: String = "http://localhost:1234") {
        Router.baseURLString = url
    }

    func setup(_ interactions: [Interaction]) -> Future<String, NSError> {
        let promise = Promise<String, NSError>()
        clean().onSuccess { _ in
            promise.completeWith(self.setupInteractions(interactions))
        }.onFailure { error in
            promise.failure(error)
        }

        return promise.future
    }

    func verify(provider: String, consumer: String) -> Future<String, NSError> {
        let promise = Promise<String, NSError>()
        verifyInteractions().onSuccess { _ in
            promise.completeWith(self.write(provider: provider, consumer: consumer))
        }.onFailure { error in
            promise.failure(error)
        }

        return promise.future
    }

    private func verifyInteractions() -> Future<String, NSError> {
        let promise = Promise<String, NSError>()
        Alamofire.request(Router.verify)
            .validate()
            .responseString { response in self.requestHandler(promise)(response) }

        return promise.future
    }

    private func write(provider: String, consumer: String) -> Future<String, NSError> {
        let promise = Promise<String, NSError>()

        Alamofire.request(Router.write(["consumer": ["name": consumer],
                                        "provider": ["name": provider]]))
            .validate()
            .responseString { response in self.requestHandler(promise)(response) }

        return promise.future
    }

    private func clean() -> Future<String, NSError> {
        let promise = Promise<String, NSError>()

        Alamofire.request(Router.clean)
            .validate()
            .responseString { response in self.requestHandler(promise)(response) }

        return promise.future
    }

    private func setupInteractions(_ interactions: [Interaction]) -> Future<String, NSError> {
        let promise = Promise<String, NSError>()
        let payload: [String: Any] = ["interactions": interactions.map { $0.payload() },
                                      "example_description": "description"]
        Alamofire.request(Router.setup(payload))
            .validate()
            .responseString { response in self.requestHandler(promise)(response) }

        return promise.future
    }

    func requestHandler(_ promise: Promise<String, NSError>) -> (DataResponse<String>) -> Void {
        return { response in
            switch response.result {
            case let .success(responseValue):
                promise.success(responseValue)
            case let .failure(error):
                let errorMessage: String
                if let errorBody = response.data {
                    errorMessage = "\(String(data: errorBody, encoding: String.Encoding.utf8)!)"
                } else {
                    errorMessage = error.localizedDescription
                }
                let userInfo = [NSLocalizedDescriptionKey: NSLocalizedString("Error", value: errorMessage, comment: "")]
                promise.failure(NSError(domain: "", code: 0, userInfo: userInfo))
            }
        }
    }
}
