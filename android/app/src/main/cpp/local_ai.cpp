#include <jni.h>
#include <llama.h>
#include <algorithm>
#include <atomic>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
struct Engine {
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
    std::atomic<bool> stop{false};
    ~Engine() {
        if (ctx) llama_free(ctx);
        if (model) llama_model_free(model);
    }
};
std::once_flag backend;
Engine *engine(jlong handle) { return reinterpret_cast<Engine *>(handle); }
bool aborted(void *data) { return static_cast<Engine *>(data)->stop.load(); }
void fail(JNIEnv *env) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Local inference failed");
}
std::string bytes(JNIEnv *env, jbyteArray input) {
    const auto size = env->GetArrayLength(input);
    if (size > 40000) throw std::runtime_error("Input too large");
    std::string text(size, '\0');
    env->GetByteArrayRegion(input, 0, size, reinterpret_cast<jbyte *>(text.data()));
    return text;
}
std::vector<llama_token> tokenize(Engine *e, const std::string &text) {
    const auto *vocab = llama_model_get_vocab(e->model);
    int count = llama_tokenize(vocab, text.data(), text.size(), nullptr, 0, true, true);
    if (count >= 0) return {};
    std::vector<llama_token> tokens(-count);
    count = llama_tokenize(vocab, text.data(), text.size(), tokens.data(), tokens.size(), true, true);
    if (count < 0) throw std::runtime_error("Tokenization failed");
    tokens.resize(count);
    return tokens;
}
}

extern "C" JNIEXPORT jlong JNICALL
Java_org_studyforge_studyforge_LocalAiBridge_nativeLoad(JNIEnv *env, jobject, jstring path) {
    try {
        std::call_once(backend, [] { llama_backend_init(); });
        auto e = std::make_unique<Engine>();
        auto mp = llama_model_default_params();
        mp.n_gpu_layers = 0;
        mp.use_mmap = true;
        mp.use_mlock = false;
        const char *filename = env->GetStringUTFChars(path, nullptr);
        if (!filename) return 0;
        e->model = llama_model_load_from_file(filename, mp);
        env->ReleaseStringUTFChars(path, filename);
        if (!e->model) throw std::runtime_error("Model load failed");
        auto cp = llama_context_default_params();
        cp.n_ctx = 2048;
        cp.n_batch = 128;
        cp.n_ubatch = 128;
        cp.n_threads = 2;
        cp.n_threads_batch = 2;
        cp.abort_callback = aborted;
        cp.abort_callback_data = e.get();
        e->ctx = llama_init_from_model(e->model, cp);
        if (!e->ctx) throw std::runtime_error("Context load failed");
        return reinterpret_cast<jlong>(e.release());
    } catch (...) { fail(env); return 0; }
}

extern "C" JNIEXPORT jint JNICALL
Java_org_studyforge_studyforge_LocalAiBridge_nativeTokenCount(JNIEnv *env, jobject, jlong handle, jbyteArray input) {
    try { return tokenize(engine(handle), bytes(env, input)).size(); }
    catch (...) { fail(env); return 0; }
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_org_studyforge_studyforge_LocalAiBridge_nativeGenerate(JNIEnv *env, jobject, jlong handle, jbyteArray input) {
    try {
        auto *e = engine(handle);
        const auto tokens = tokenize(e, bytes(env, input));
        if (tokens.empty() || tokens.size() > 1500) throw std::runtime_error("Context limit");
        llama_memory_clear(llama_get_memory(e->ctx), true);
        std::string output;
        for (size_t pos = 0; pos < tokens.size() && !e->stop; pos += 128) {
            auto batch = llama_batch_get_one(const_cast<llama_token *>(tokens.data()) + pos,
                std::min<size_t>(128, tokens.size() - pos));
            if (llama_decode(e->ctx, batch) != 0) {
                if (e->stop) break;
                throw std::runtime_error("Prompt decode failed");
            }
        }
        auto sp = llama_sampler_chain_default_params();
        std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(
            llama_sampler_chain_init(sp), llama_sampler_free);
        llama_sampler_chain_add(sampler.get(), llama_sampler_init_top_k(40));
        llama_sampler_chain_add(sampler.get(), llama_sampler_init_top_p(0.9f, 1));
        llama_sampler_chain_add(sampler.get(), llama_sampler_init_temp(0.3f));
        llama_sampler_chain_add(sampler.get(), llama_sampler_init_dist(42));
        const auto *vocab = llama_model_get_vocab(e->model);
        for (int i = 0; i < 400 && !e->stop; ++i) {
            auto token = llama_sampler_sample(sampler.get(), e->ctx, -1);
            if (llama_vocab_is_eog(vocab, token)) break;
            char piece[256];
            int n = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, false);
            if (n >= 0) {
                output.append(piece, n);
            } else {
                std::vector<char> bigger(-n);
                n = llama_token_to_piece(vocab, token, bigger.data(), bigger.size(), 0, false);
                if (n < 0) throw std::runtime_error("Token decode failed");
                output.append(bigger.data(), n);
            }
            auto batch = llama_batch_get_one(&token, 1);
            if (llama_decode(e->ctx, batch) != 0) {
                if (e->stop) break;
                throw std::runtime_error("Generation decode failed");
            }
        }
        auto result = env->NewByteArray(output.size());
        if (result) env->SetByteArrayRegion(result, 0, output.size(),
            reinterpret_cast<const jbyte *>(output.data()));
        return result;
    } catch (...) { fail(env); return nullptr; }
}

extern "C" JNIEXPORT void JNICALL
Java_org_studyforge_studyforge_LocalAiBridge_nativeStop(JNIEnv *, jobject, jlong handle) {
    engine(handle)->stop = true;
}
extern "C" JNIEXPORT void JNICALL
Java_org_studyforge_studyforge_LocalAiBridge_nativeFree(JNIEnv *, jobject, jlong handle) {
    delete engine(handle);
}

extern "C" JNIEXPORT void JNICALL
Java_org_studyforge_studyforge_LocalAiBridge_nativeResetStop(JNIEnv *, jobject, jlong handle) {
    engine(handle)->stop = false;
}
