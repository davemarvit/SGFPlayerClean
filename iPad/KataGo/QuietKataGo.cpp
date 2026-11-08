#include "QuietKataGo.h"
#include "core/global.h"
#include "core/logger.h"
#include "game/board.h"
#include "game/boardhistory.h"
#include "neuralnet/nneval.h"
#include "neuralnet/nninterface.h"
#include "search/search.h"
#include "external/nlohmann_json/json.hpp"
#include <atomic>
#include <memory>
#include <mutex>
#include <cstring>
using json = nlohmann::json;
static std::atomic<bool> cancelled(false);
static std::atomic<bool> stopSearch(false);
static std::mutex operation;
static std::once_flag initialization;
// Process-lifetime owner avoids C++ static destruction while worker threads
// still exist. QKGUnload explicitly releases the evaluator on suspension.
struct EngineState { Logger logger; std::unique_ptr<NNEvaluator> evaluator; };
static EngineState& engine() { static auto* state = new EngineState(); return *state; }
static Player color(const std::string& value) {
    if(value == "B") return P_BLACK;
    if(value == "W") return P_WHITE;
    throw std::runtime_error("Invalid player");
}
static Loc location(int x, int y, const Board& board) {
    if(x == -1 && y == -1) return Board::PASS_LOC;
    if(x < 0 || y < 0 || x >= board.x_size || y >= board.y_size) throw std::runtime_error("Invalid coordinate");
    return Location::getLoc(x,y,board.x_size);
}
extern "C" char *QKGAnalyze(const char *modelPath, const char *requestJSON) {
    std::lock_guard<std::mutex> lock(operation);
    auto& evaluator = engine().evaluator;
    auto& logger = engine().logger;
    json result;
    try {
        if(cancelled.load()) throw std::runtime_error("Analysis cancelled");
        std::call_once(initialization, [] { Board::initHash(); ScoreValue::initTables(); NeuralNet::globalInitialize(); });
        json request = json::parse(requestJSON);
        int size = request.at("boardSize").get<int>();
        if(size < 2 || size > 19) throw std::runtime_error("On-device analysis supports boards up to 19x19");
        Rules rules = Rules::parseRulesWithoutKomi(request.at("rules"), request.at("komi"));
        Board board(size,size);
        for(const auto& stone : request.at("initial")) {
            Loc loc = location(stone.at("x"),stone.at("y"),board);
            if(loc == Board::PASS_LOC || !board.setStone(loc,color(stone.at("color")))) throw std::runtime_error("Invalid setup stones");
        }
        Player next = color(request.at("initialPlayer"));
        BoardHistory history(board,next,rules,0);
        for(const auto& move : request.at("moves")) {
            Player pla = color(move.at("color"));
            Loc loc = location(move.at("x"),move.at("y"),board);
            if(!history.isLegal(board,loc,pla)) throw std::runtime_error("Illegal move in game history");
            history.makeBoardMoveAssumeLegal(board,loc,pla,nullptr);
            next = getOpp(pla);
        }
        next = color(request.at("nextPlayer"));
        if(!evaluator) {
            evaluator = std::make_unique<NNEvaluator>("QuietGo",modelPath,"",&logger,1,19,19,false,true,12,8,false,"","",false,enabled_t::False,enabled_t::True,1,std::vector<int>{-1},"QuietGo-iPad",false,0);
            evaluator->spawnServerThreads();
        }
        SearchParams params;
        params.maxVisits = std::max(1,std::min(128,request.value("visits",16)));
        params.maxTime = 8.0;
        params.numThreads = 1;
        Search search(params,evaluator.get(),&logger,"QuietGo-iPad-search");
        search.setPosition(next,board,history);
        search.runWholeSearch(stopSearch);
        if(cancelled.load()) throw std::runtime_error("Analysis cancelled");
        if(!search.getAnalysisJson(P_BLACK,12,false,false,false,false,false,false,false,result)) throw std::runtime_error("No analysis result");
    } catch(const std::exception& e) { result = {{"error",e.what()}}; }
    catch(...) { result = {{"error","Unknown engine error"}}; }
    return strdup(result.dump().c_str());
}
extern "C" void QKGPrepare() { cancelled.store(false); stopSearch.store(false); }
extern "C" void QKGCancel() { cancelled.store(true); stopSearch.store(true); }
extern "C" void QKGUnload() { std::lock_guard<std::mutex> lock(operation); engine().evaluator.reset(); }
extern "C" void QKGFree(char *result) { free(result); }
