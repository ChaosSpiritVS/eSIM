import Foundation
import CoreData

// 轻量 Core Data 栈（不依赖 .xcdatamodeld），用于缓存列表数据
final class CoreDataStack {
    static let shared = CoreDataStack()

    let model: NSManagedObjectModel
    let coordinator: NSPersistentStoreCoordinator
    let context: NSManagedObjectContext

    private init() {
        // 1) 动态模型：仅一个实体 CacheEntry(key:String, value:Binary, updatedAt:Date)
        let entity = NSEntityDescription()
        entity.name = "CacheEntry"
        entity.managedObjectClassName = NSStringFromClass(CacheEntry.self)

        let keyAttr = NSAttributeDescription()
        keyAttr.name = "key"
        keyAttr.attributeType = .stringAttributeType
        keyAttr.isOptional = false
        keyAttr.isIndexed = true

        let valueAttr = NSAttributeDescription()
        valueAttr.name = "value"
        valueAttr.attributeType = .binaryDataAttributeType
        valueAttr.isOptional = false

        let updatedAtAttr = NSAttributeDescription()
        updatedAtAttr.name = "updatedAt"
        updatedAtAttr.attributeType = .dateAttributeType
        updatedAtAttr.isOptional = false

        entity.properties = [keyAttr, valueAttr, updatedAtAttr]

        // 2) 模型与协调器
        model = NSManagedObjectModel()
        model.entities = [entity]

        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

        // 3) SQLite 存储放在 Caches 目录（系统可清理）
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let storeURL = caches.appendingPathComponent("SimigoCache.sqlite")
        let options: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        do {
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
        } catch {
            // 若持久化失败，降级为内存存储，保证功能可用
            try? coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        }

        context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

// NSManagedObject 子类：与动态实体匹配
final class CacheEntry: NSManagedObject {
    @NSManaged var key: String
    @NSManaged var value: Data
    @NSManaged var updatedAt: Date
}