import Foundation
import XCTest
import PackStream
import Socket
import Result

@testable import Theo

#if os(Linux)
    import Dispatch
#endif

let TheoTimeoutInterval: TimeInterval = 10

class ConfigLoader: NSObject {

    class func loadBoltConfig() -> BoltConfig {

        let testPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent().path

        let filePath = "\(testPath)/TheoBoltConfig.json"

        return BoltConfig(pathToFile: filePath)
    }

}

class Theo_001_BoltClientTests: XCTestCase {

    let configuration: BoltConfig = ConfigLoader.loadBoltConfig()


    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func performConnect(client: BoltClient, completionBlock: (() -> ())? = nil) {
//        let connectGroup = DispatchGroup()
//        connectGroup.enter()
        client.connect() { connectionResult in
            switch connectionResult {
            case let .failure(error):
                print("Oh no! \(error)")
//                print("Error connecting: \(error)")
//                if error.errorCode == -9806 {
//                    self.performConnect(client: client) {
//                        connectGroup.leave()
//                    }
//                } else {
//                    XCTFail()
//                    connectGroup.leave()
//                }
            case let .success(isConnected):
                if !isConnected {
                    print("Error, could not connect!")
                }
            }
//            connectGroup.leave()
        }
//        print("Waiting")
//        connectGroup.wait()
//        print("Done waiting")
    }

    private func makeClient() throws -> BoltClient {
        let client = try BoltClient(hostname: configuration.hostname,
                                    port: configuration.port,
                                    username: configuration.username,
                                    password: configuration.password,
                                    encrypted: configuration.encrypted)

        performConnect(client: client)

        print(" --- done connecting ---")
        return client
    }

    func testNodeResult() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testNodeResult")

        XCTAssertTrue(client.executeCypherSync("CREATE (n:TheoTestNodeWithALongLabel { foo: \"bar\", baz: 3}) RETURN n").isSuccess)
        exp.fulfill()

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testRelationshipResult() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testNodeResult")

        let query = """
                    CREATE (b:Candidate {name:'Bala'})
                    CREATE (e:Employer {name:'Yahoo'})
                    CREATE (b)-[r:WORKED_IN]->(e)
                    RETURN b,r,e
                    """

        XCTAssertTrue(client.executeCypherSync(query).isSuccess)
        exp.fulfill()

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testIntroToCypher() throws {

        let client = try makeClient()
        let exp = self.expectation(description: "testNodeResult")
        var queries = [String]()

        queries.append(
                   """
                     MATCH (n)
                     DETACH DELETE n
                   """)

        queries.append(
                   """
                      CREATE (you:Person {name:"You"})
                      RETURN you
                   """)

        queries.append(
                   """
                      MATCH  (you:Person {name:"You"})
                      CREATE (you)-[like:LIKE]->(neo:Database {name:"Neo4j" })
                      RETURN you,like,neo
                   """)

        queries.append(
                   """
                      MATCH (you:Person {name:"You"})
                      FOREACH (name in ["Johan","Rajesh","Anna","Julia","Andrew"] |
                      CREATE (you)-[:FRIEND]->(:Person {name:name}))
                   """)

        queries.append(
                   """
                      MATCH (you {name:"You"})-[:FRIEND]->(yourFriends)
                      RETURN you, yourFriends
                   """)

        queries.append(
                   """
                      MATCH (neo:Database {name:"Neo4j"})
                      MATCH (anna:Person {name:"Anna"})
                      CREATE (anna)-[:FRIEND]->(:Person:Expert {name:"Amanda"})-[:WORKED_WITH]->(neo)
                   """)

        queries.append(
                   """
                      MATCH (you {name:"You"})
                      MATCH (expert)-[w:WORKED_WITH]->(db:Database {name:"Neo4j"})
                      MATCH path = shortestPath( (you)-[:FRIEND*..5]-(expert) )
                      RETURN DISTINCT db,w,expert,path
                   """)

        for query in queries {
            print(query)
            XCTAssertTrue(client.executeCypherSync(query).isSuccess)

        }
        exp.fulfill()

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testSetOfQueries() throws {

        let client = try makeClient()
        let exp = self.expectation(description: "testSetOfQueries")
        var queries = [String]()

        queries.append(
            """
              CREATE (you:Person {name:"You", weight: 80})
              RETURN you.name, sum(you.weight) as singleSum
            """)

        queries.append(
            """
              MATCH (you:Person {name:"You"})
              RETURN you.name, sum(you.weight) as allSum, you
            """)


        for query in queries {
            print(query)
            XCTAssertTrue(client.executeCypherSync(query).isSuccess)

        }
        exp.fulfill()

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }


    func testSucceedingTransactionSync() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testSucceedingTransaction")

        do {
            try client.executeAsTransaction() { (tx) in
                XCTAssertTrue(client.executeCypherSync("CREATE (n:TheoTestNode { foo: \"bar\"})").isSuccess)
                XCTAssertTrue(client.executeCypherSync("MATCH (n:TheoTestNode { foo: \"bar\"}) RETURN n").isSuccess)
                XCTAssertTrue(client.executeCypherSync("MATCH (n:TheoTestNode { foo: \"bar\"}) DETACH DELETE n").isSuccess)
                exp.fulfill()
            }
        } catch let error {
            print("Failed transaction with error \(error)")
            XCTFail()
        }

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testFailingTransactionSync() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testFailingTransaction")

        try client.executeAsTransaction() { (tx) in
            XCTAssertTrue(client.executeCypherSync("CREATE (n:TheoTestNode { foo: \"bar\"})").isSuccess)
            XCTAssertTrue(client.executeCypherSync("MATCH (n:TheoTestNode { foo: \"bar\"}) RETURN n").isSuccess)
            XCTAssertFalse(client.executeCypherSync("MAXXXTCH (n:TheoTestNode { foo: \"bar\"}) DETACH DELETE n").isSuccess)
            tx.markAsFailed()

            XCTAssertFalse(tx.succeed)
            exp.fulfill()
        }

        self.waitForExpectations(timeout: TheoTimeoutInterval, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testCancellingTransaction() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testCancellingTransaction")

        try client.executeAsTransaction() { (tx) in
            tx.markAsFailed()
            exp.fulfill()
        }

        self.waitForExpectations(timeout: TheoTimeoutInterval, handler: { error in
            XCTAssertNil(error)
        })

    }

    func testTransactionResultsInBookmark() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testTransactionResultsInBookmark")

        try client.executeAsTransaction() { (tx) in
            client.executeCypher("CREATE (n:TheoTestNode { foo: \"bar\"})") { result in
                switch result {
                case let .failure(error):
                    print("Error in cypher: \(error)")
                case let .success((success, partialQueryResult)):
                    if success {
                        client.pullAll(partialQueryResult: partialQueryResult) { result in
                            switch result {
                            case let .failure(error):
                                print("Error in cypher: \(error)")
                            case let .success((success, queryResult)):
                                XCTAssertTrue(success)
                                XCTAssertEqual(1, queryResult.stats.propertiesSetCount)
                                XCTAssertEqual(1, queryResult.stats.labelsAddedCount)
                                XCTAssertEqual(1, queryResult.stats.nodesCreatedCount)
                                XCTAssertEqual("w", queryResult.stats.type)
                                XCTAssertEqual(0, queryResult.fields.count)
                                XCTAssertEqual(0, queryResult.nodes.count)
                                XCTAssertEqual(0, queryResult.relationships.count)
                                XCTAssertEqual(0, queryResult.paths.count)
                                XCTAssertEqual(0, queryResult.responseItemDicts.count)
                            }
                        }
                    } else {
                        XCTFail("Query failed somehow")
                    }

                }

                XCTAssertTrue(result.isSuccess)
            }

            exp.fulfill()
        }

        if let bookmark = client.getBookmark() {
            XCTAssertNotEqual("", bookmark)

            #if swift(>=4.0)
                let endIndex = bookmark.index(bookmark.startIndex, offsetBy: 17)
                let substring = bookmark[..<endIndex]
                XCTAssertEqual("neo4j:bookmark:v1", String(substring))
            #elseif swift(>=3.0)
                XCTAssertEqual("neo4j:bookmark:v1", bookmark.substring(to: bookmark.index(bookmark.startIndex, offsetBy: 17)))
            #endif

        } else {
            XCTFail("Bookmark should not be nil")
        }

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }

    func testGettingStartedExample() throws {
        let client = try makeClient()
        let exp = self.expectation(description: "testGettingStartedExample")

        // First, lets determine the number of existing King Arthurs. The test may have been run before

        let figureOutNumberOfKingArthurs = DispatchGroup()
        figureOutNumberOfKingArthurs.enter()
        var numberOfKingArthurs = -1

        client.executeCypher("MATCH (a:Person) WHERE a.name = {name} RETURN count(a) AS count", params: ["name": "Arthur"])  { result in

            XCTAssertTrue(result.isSuccess)
            XCTAssertTrue(result.value!.0)

            client.pullAll(partialQueryResult: result.value!.1) { response in
                switch result {
                case .failure:
                    XCTFail("Failed to pull response data")
                case let .success((success, queryResult)):
                    XCTAssertTrue(success)
                    XCTAssertEqual(1, queryResult.responseItemDicts.count)
                    XCTAssertEqual(1, queryResult.responseItemDicts.first!.count)
                    XCTAssertEqual(0, queryResult.nodes.count)
                    XCTAssertEqual(0, queryResult.relationships.count)
                    XCTAssertEqual(0, queryResult.paths.count)
                    XCTAssertEqual(1, queryResult.fields.count)

                    numberOfKingArthurs = Int(queryResult.responseItemDicts.first?["count"] as! UInt64)
                    XCTAssertGreaterThanOrEqual(0, numberOfKingArthurs)

                }


                figureOutNumberOfKingArthurs.leave()
            }
        }
        figureOutNumberOfKingArthurs.wait()
        XCTAssertNotEqual(-1, numberOfKingArthurs)

        // Now lets run the actual test

        try client.executeAsTransaction() { (tx) in
            let result = client.executeCypherSync("CREATE (a:Person {name: {name}, title: {title}})",
                                                   params: ["name": "Arthur", "title": "King"])
            XCTAssertTrue(result.isSuccess)
            let queryResult = result.value!
            XCTAssertEqual(2, queryResult.stats.propertiesSetCount)
            XCTAssertEqual(1, queryResult.stats.labelsAddedCount)
            XCTAssertEqual(1, queryResult.stats.nodesCreatedCount)
            XCTAssertEqual("w", queryResult.stats.type)
            XCTAssertEqual(0, queryResult.fields.count)
            XCTAssertEqual(0, queryResult.nodes.count)
            XCTAssertEqual(0, queryResult.relationships.count)
            XCTAssertEqual(0, queryResult.paths.count)
            XCTAssertEqual(0, queryResult.responseItemDicts.count)


            client.executeCypher("MATCH (a:Person) WHERE a.name = {name} " +
            "RETURN a.name AS name, a.title AS title", params: ["name": "Arthur"])  { result in

                XCTAssertTrue(result.isSuccess)
                XCTAssertTrue(result.value!.0)
                let queryResult = result.value!.1

                XCTAssertEqual(2, queryResult.fields.count)
                XCTAssertEqual(0, queryResult.nodes.count)
                XCTAssertEqual(0, queryResult.relationships.count)
                XCTAssertEqual(0, queryResult.paths.count)
                XCTAssertEqual(0, queryResult.responseItemDicts.count)

                client.pullAll(partialQueryResult: queryResult) { result in

                    switch result {
                    case .failure(_):
                        XCTFail("Failed to pull response data")
                    case let.success((success, queryResult)):
                        XCTAssertTrue(success)
                        
                        XCTAssertEqual("r", queryResult.stats.type)
                        XCTAssertEqual(2, queryResult.fields.count)
                        XCTAssertEqual(0, queryResult.nodes.count)
                        XCTAssertEqual(0, queryResult.relationships.count)
                        XCTAssertEqual(0, queryResult.paths.count)
                        XCTAssertEqual(1, queryResult.responseItemDicts.count)
                        let row = queryResult.responseItemDicts.first!
                        XCTAssertEqual(2, row.count)
                        XCTAssertEqual("King", row["title"] as! String)
                        XCTAssertEqual("Arthur", row["name"] as! String)

                        
                        XCTAssertEqual(numberOfKingArthurs + 2, queryResult.responseItemDicts.first?.count ?? 0)

                        tx.markAsFailed() // This should undo the beginning CREATE even though we have pulled it here
                        exp.fulfill()
                    }
                }
            }
        }

        self.waitForExpectations(timeout: 10, handler: { error in
            XCTAssertNil(error)
        })
    }
    
    func testCreateAndRunCypherFromNode() throws {
        
        let node = Node(labels: ["Person","Husband","Father"], properties: [
            "firstName": "Niklas",
            "age": 38,
            "weight": 80.2,
            "favouriteWhiskys": List(items: ["Ardbeg", "Caol Ila", "Laphroaig"])
            ])
        
        let client = try makeClient()
        let result = client.createAndReturnNodeSync(node: node)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(resultNode):
            XCTAssertEqual(3, resultNode.labels.count)
            XCTAssertEqual(4, resultNode.properties.count)
            XCTAssertEqual("Niklas", resultNode.properties["firstName"] as! String)
            XCTAssertEqual(38 as Int64, resultNode.properties["age"]?.intValue())
        }
    }

    func makeSomeNodes() -> [Node] {
        let node1 = Node(labels: ["Person","Husband","Father"], properties: [
            "firstName": "Niklas",
            "age": 38,
            "weight": 80.2,
            "favouriteWhiskys": List(items: ["Ardbeg", "Caol Ila", "Laphroaig"])
            ])
        
        let node2 = Node(labels: ["Person","Wife","Mother"], properties: [
            "firstName": "Christina",
            "age": 37,
            "favouriteAnimals": List(items: ["Silver", "Oscar", "Simba"])
            ])

        return [node1, node2]
    }
    
    func testCreateAndRunCypherFromNodesWithResult() throws {
        
        let nodes = makeSomeNodes()
        
        let client = try makeClient()
        let result = client.createAndReturnNodesSync(nodes: nodes)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(resultNodes):
            var resultNode = resultNodes.filter { $0.properties["firstName"] as! String == "Niklas" }.first!
            XCTAssertEqual(3, resultNode.labels.count)
            XCTAssertTrue(resultNode.labels.contains("Father"))
            XCTAssertEqual(4, resultNode.properties.count)
            XCTAssertEqual("Niklas", resultNode.properties["firstName"] as! String)
            XCTAssertEqual(38 as Int64, resultNode.properties["age"]?.intValue())

            resultNode = resultNodes.filter { $0.properties["firstName"] as! String == "Christina" }.first!
            XCTAssertEqual(3, resultNode.labels.count)
            XCTAssertTrue(resultNode.labels.contains("Mother"))
            XCTAssertEqual(3, resultNode.properties.count)
            XCTAssertEqual("Christina", resultNode.properties["firstName"] as! String)
            XCTAssertEqual(37 as Int64, resultNode.properties["age"]?.intValue())
        }
    }
    
    func testUpdateAndRunCypherFromNodesWithResult() throws {
        
        let nodes = makeSomeNodes()
        
        let client = try makeClient()
        var result = client.createAndReturnNodesSync(nodes: nodes)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case var .success(resultNodes):
            var resultNode = resultNodes.filter { $0.properties["firstName"] as! String == "Niklas" }.first!
            var resultNode2 = resultNodes.filter { $0.properties["firstName"] as! String == "Christina" }.first!
            
            resultNode["instrument"] = "Recorder"
            resultNode["favouriteComposer"] = "CPE Bach"
            resultNode["weight"] = nil
            resultNode.add(label: "LabelledOne")
            
            resultNode2["instrument"] = "Piano"
            resultNode2.add(label: "LabelledOne")
            result = client.updateAndReturnNodesSync(nodes: [resultNode, resultNode2])
            XCTAssertNotNil(result.value)
            resultNodes = result.value!
            
            let resultNode3 = resultNodes.filter { $0.properties["firstName"] as! String == "Niklas" }.first!
            XCTAssertEqual(4, resultNode3.labels.count)
            XCTAssertTrue(resultNode3.labels.contains("Father"))
            XCTAssertTrue(resultNode3.labels.contains("LabelledOne"))
            XCTAssertEqual(5, resultNode3.properties.count)
            XCTAssertNil(resultNode3["weight"])
            XCTAssertEqual("Niklas", resultNode3.properties["firstName"] as! String)
            XCTAssertEqual(38 as Int64, resultNode3.properties["age"]?.intValue())
            
            let resultNode4 = resultNodes.filter { $0.properties["firstName"] as! String == "Christina" }.first!
            XCTAssertEqual(4, resultNode4.labels.count)
            XCTAssertTrue(resultNode4.labels.contains("Mother"))
            XCTAssertTrue(resultNode4.labels.contains("LabelledOne"))
            XCTAssertEqual(4, resultNode4.properties.count)
            XCTAssertEqual("Christina", resultNode4.properties["firstName"] as! String)
            XCTAssertEqual(37 as Int64, resultNode4.properties["age"]?.intValue())

        }
    }
    
    func testCreateAndRunCypherFromNodesNoResult() throws {

        let nodes = makeSomeNodes()

        let client = try makeClient()
        let result = client.createNodesSync(nodes: nodes)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(isSuccess):
            XCTAssertTrue(isSuccess)
        }

    }
    
    func testCreateAndRunCypherFromNodeNoResult() throws {
        
        let nodes = makeSomeNodes()
        
        let client = try makeClient()
        let result = client.createNodeSync(node: nodes.first!)
        switch result {
        case let .failure(error):
            XCTFail(error.localizedDescription)
        case let .success(isSuccess):
            XCTAssertTrue(isSuccess)
        }
        
    }
    
    func testUpdateNodesWithResult() throws {
        
        let node = makeSomeNodes().first!
        let client = try makeClient()
        var result = client.createAndReturnNodeSync(node: node)
        let createdNode = result.value!
        
        createdNode["favouriteColor"] = "Blue"
        createdNode["luckyNumber"] = 24
        createdNode.add(label: "RecorderPlayer")

        result = client.updateAndReturnNodeSync(node: createdNode)
        let updatedNode = result.value!
        
        XCTAssertEqual(4, updatedNode.labels.count)
        XCTAssertEqual(Int64(24), updatedNode["luckyNumber"]!.intValue()!)
    }
    
    func testUpdateNodesWithNoResult() throws {
        
        let node = makeSomeNodes().first!
        let client = try makeClient()
        let result = client.createAndReturnNodeSync(node: node)
        let createdNode = result.value!
        
        createdNode["favouriteColor"] = "Blue"
        createdNode["luckyNumber"] = 24
        createdNode.add(label: "RecorderPlayer")
        
        let emptyResult = client.updateNodeSync(node: createdNode)
        let isSuccess = emptyResult.value!
        XCTAssertTrue(isSuccess)
    }
    
    func testCreateRelationship() throws {
        
        let client = try makeClient()
        let nodes = makeSomeNodes()
        let createdNodes = client.createAndReturnNodesSync(nodes: nodes).value!
        let (from, to) = (createdNodes[0], createdNodes[1])
        let result = client.relateSync(node: from, to: to, name: "Married", properties: [ "happily": true ])
        let createdRelationship: Relationship = result.value!
        
        XCTAssertTrue(createdRelationship["happily"] as! Bool)
        XCTAssertEqual(from.id!, createdRelationship.fromNodeId)
        XCTAssertEqual(to.id!, createdRelationship.toNodeId)
    }
    
    func testUpdateRelationship() throws {
        
        let exp = expectation(description: "Finish transaction with updates to relationship")
        let client = try makeClient()
        try client.executeAsTransaction() { tx in
        
            let nodes = self.makeSomeNodes()
            let createdNodes = client.createAndReturnNodesSync(nodes: nodes).value!
            let (from, to) = (createdNodes[0], createdNodes[1])
            var result = client.relateSync(node: from, to: to, name: "Married", properties: [ "happily": true ])
            let createdRelationship: Relationship = result.value!
            
            XCTAssertTrue(createdRelationship["happily"] as! Bool)
            XCTAssertEqual(from.id!, createdRelationship.fromNodeId)
            XCTAssertEqual(to.id!, createdRelationship.toNodeId)
            
            createdRelationship["location"] = "church"
            createdRelationship["someProp"] = 42
            result = client.updateAndReturnRelationshipSync(relationship: createdRelationship)
            let updatedRelationship: Relationship = result.value!
            
            updatedRelationship["someProp"] = nil
            result = client.updateAndReturnRelationshipSync(relationship: updatedRelationship)
            let finalRelationship: Relationship = result.value!
            
            XCTAssertTrue(finalRelationship["happily"] as! Bool)
            XCTAssertEqual("church", finalRelationship["location"] as! String)
            XCTAssertNil(finalRelationship["someProp"])
            XCTAssertEqual(from.id!, finalRelationship.fromNodeId)
            XCTAssertEqual(to.id!, finalRelationship.toNodeId)
            
            tx.markAsFailed()
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10.0) { error in
            XCTAssertNil(error)
        }
    }

    static var allTests = [
        ("testNodeResult", testNodeResult),
        ("testRelationshipResult", testRelationshipResult),
        ("testIntroToCypher", testIntroToCypher),
        ("testSetOfQueries", testSetOfQueries),
        ("testSucceedingTransactionSync", testSucceedingTransactionSync),
        ("testFailingTransactionSync", testFailingTransactionSync),
        ("testCancellingTransaction", testCancellingTransaction),
        ("testTransactionResultsInBookmark", testTransactionResultsInBookmark),
        ("testGettingStartedExample", testGettingStartedExample),
        ("testCreateAndRunCypherFromNode", testCreateAndRunCypherFromNode),
        ("testUpdateNodesWithResult", testUpdateNodesWithResult),
        ("testUpdateNodesWithNoResult", testUpdateNodesWithNoResult),
        ("testCreateRelationship", testCreateRelationship),
        ("testUpdateRelationship", testUpdateRelationship),
        ("testCreateAndRunCypherFromNodeNoResult", testCreateAndRunCypherFromNodeNoResult),
    ]

}

extension Result {
    var isSuccess: Bool {
        get {
            switch self {
            case .failure(_):
                return false
            case .success(_):
                return true
            }
        }
    }
}
