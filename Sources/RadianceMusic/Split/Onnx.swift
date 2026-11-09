import Foundation
import OnnxRuntimeBindings

/** ONNX Runtime on the iPhone (the splitter's models run on it, as on Android). */
enum Onnx {
    /** Its version, for About and the logs. */
    static var version: String { ORTVersion() ?? "?" }

    /** A session for a model file, on the CPU, with [threads] threads. */
    static func session(_ model: URL, threads: Int32 = 2) throws -> (ORTEnv, ORTSession) {
        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(threads)
        try options.setGraphOptimizationLevel(.all)
        let session = try ORTSession(env: env, modelPath: model.path, sessionOptions: options)
        return (env, session)
    }
}
