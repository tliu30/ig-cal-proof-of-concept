/// GenerateCache.swift
/// ==================
/// Command-line tool that pre-computes the llama.cpp KV cache for the static
/// system prompt. The resulting cache file is bundled with the iOS app so that
/// first-launch inference skips the ~130s prompt-processing step.
///
/// Usage:
///   generate-cache <model-path> <output-cache-path>
///
/// The tool uses the same model parameters as the iOS app (CPU-only, n_ctx=4096,
/// n_batch=512) to ensure the saved KV cache state is binary-compatible.

import Foundation
import LlamaSwift

@main
enum GenerateCache {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            print("Usage: generate-cache <model-path> <output-cache-path>")
            print("  model-path         Path to the .gguf model file")
            print("  output-cache-path  Where to write system-prompt-cache.bin")
            exit(1)
        }

        let modelPath = args[1]
        let outputPath = args[2]

        guard FileManager.default.fileExists(atPath: modelPath) else {
            print("Error: Model file not found at: \(modelPath)")
            exit(1)
        }

        // --- Initialize llama.cpp backend ---
        llama_backend_init()
        defer { llama_backend_free() }

        // --- Load model (CPU-only, matching iOS app) ---
        print("Loading model from: \(modelPath)")
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = 0 // CPU-only to match iOS app
        guard let model = llama_model_load_from_file(modelPath, mparams) else {
            print("Error: Failed to load model")
            exit(1)
        }
        defer { llama_model_free(model) }

        // --- Create context (matching iOS app params) ---
        var cparams = llama_context_default_params()
        cparams.n_ctx = 4096
        cparams.n_batch = 512
        guard let ctx = llama_init_from_model(model, cparams) else {
            print("Error: Failed to create context")
            exit(1)
        }
        defer { llama_free(ctx) }

        let vocab = llama_model_get_vocab(model)!

        // --- Tokenize the static system prompt ---
        // Uses the shared llamaSystemPromptPrefix from LlamaSystemPrompt.swift (symlinked).
        // This includes the ChatML wrapper: <|im_start|>system\n...<|im_end|>\n<|im_start|>user\n
        let systemPrefix = llamaSystemPromptPrefix
        let nBytes = Int32(systemPrefix.utf8.count)
        let maxTokens = nBytes + 64
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))

        let nTokens = systemPrefix.withCString { cStr in
            llama_tokenize(vocab, cStr, nBytes, &tokens, maxTokens, true, true)
        }
        guard nTokens > 0 else {
            print("Error: Tokenization failed")
            exit(1)
        }
        print("Tokenized system prompt: \(nTokens) tokens")

        // --- Decode tokens through the model (the expensive part) ---
        print("Decoding system prompt...")
        let startTime = Date()
        var nProcessed: Int32 = 0
        let batchSize: Int32 = 512

        while nProcessed < nTokens {
            let remaining = nTokens - nProcessed
            let currentBatch = min(remaining, batchSize)
            let result: Int32 = tokens.withUnsafeMutableBufferPointer { buf in
                let ptr = buf.baseAddress! + Int(nProcessed)
                return llama_decode(ctx, llama_batch_get_one(ptr, currentBatch))
            }
            if result != 0 {
                print("Error: Decode failed at token \(nProcessed)")
                exit(1)
            }
            nProcessed += currentBatch
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("Decoded \(nTokens) tokens in \(String(format: "%.1f", elapsed))s")

        // --- Save KV cache state to disk ---
        let saved = tokens.withUnsafeBufferPointer { buf in
            llama_state_save_file(ctx, outputPath, buf.baseAddress!, Int(nTokens))
        }
        guard saved else {
            print("Error: Failed to save cache to: \(outputPath)")
            exit(1)
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0
        let sizeMB = Double(fileSize) / 1_048_576.0
        print("Cache saved to: \(outputPath) (\(String(format: "%.1f", sizeMB)) MB, \(nTokens) tokens)")
    }
}
