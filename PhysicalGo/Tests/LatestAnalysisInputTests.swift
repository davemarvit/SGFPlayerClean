import Foundation
@main struct LatestAnalysisInputTests {
    static func main() {
        var q=LatestAnalysisInput<Int>()
        q.offer(1,capturedAt:10,revision:1)
        q.offer(2,capturedAt:10.1,revision:1)
        q.offer(0,capturedAt:10.05,revision:1)
        precondition(q.take(now:10.15,revision:1)==2,"Busy recognition did not retain only the newest frame")
        precondition(q.take(now:10.16,revision:1)==nil,"Frame processed twice")
        for now in [9.0,10.201,Double.nan,Double.infinity] {
            q.offer(3,capturedAt:10,revision:1)
            precondition(q.take(now:now,revision:1)==nil,"Old/future/invalid frame admitted")
            precondition(q.take(now:10.1,revision:1)==nil,"Rejected input remained queued")
        }
        q.offer(4,capturedAt:10,revision:1)
        precondition(q.take(now:10.1,revision:2)==nil,"Old camera context admitted")
        q.offer(5,capturedAt:10,revision:1)
        q.offer(6,capturedAt:9,revision:2)
        precondition(q.take(now:9.1,revision:2)==6,"New context did not replace waiting old context")
        q.offer(7,capturedAt:.nan,revision:2)
        precondition(q.take(now:10,revision:2)==nil,"Invalid timestamp queued")
        print("PASS: latest-only analysis input; ordering, duplicate consumption, age and context rejection")
    }
}
