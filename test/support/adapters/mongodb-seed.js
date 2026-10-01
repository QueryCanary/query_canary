const database = db.getSiblingDB("test_db");
database.numbers.deleteMany({});
database.numbers.insertMany([
  {_id: ObjectId("507f1f77bcf86cd799439011"), value: 10, created_at: ISODate("2025-01-01T12:00:00Z"), nested: {enabled: true}},
  {_id: ObjectId("507f1f77bcf86cd799439012"), value: 20, created_at: ISODate("2025-01-02T12:00:00Z"), nested: {enabled: false}},
  {_id: ObjectId("507f1f77bcf86cd799439013"), value: 30, created_at: ISODate("2025-01-03T12:00:00Z"), amount: NumberDecimal("12.50")}
]);
