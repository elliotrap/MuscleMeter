//
//  ExerciseModel.swift
//  WorkoutProgressApp
//
//  Created by Elliot Rapp on 2/11/25.
//

import SwiftUI
import CloudKit
import Foundation



struct Exercise: Identifiable {
    let id = UUID()
    
    var recordID: CKRecord.ID?
    var name: String
    var sets: Int
    var reps: Int
    var setWeights: [Double]
    var setCompletions: [Bool]
    var setNotes: [String]
    var exerciseNote: String
    var setActualReps: [Int]
    var timestamp: Date
    
}

class ExerciseViewModel: ObservableObject {
    @Published var exercises: [Exercise] = []
    let workoutID: CKRecord.ID
    
    private let privateDatabase = CKContainer.default().privateCloudDatabase

    init(workoutID: CKRecord.ID) {
        self.workoutID = workoutID
    }
    
    func addExercise(
        name: String,
        sets: Int,
        reps: Int,
        setWeights: [Double],
        exerciseNote: String = "",
        setCompletions: [Bool]
    ) {
        print("ExerciseViewModel: Creating exercise locally with:")
        print("  Name: \(name)")
        print("  Sets: \(sets)")
        print("  Reps: \(reps)")
        print("  setWeights: \(setWeights)")
        print("  setCompletions: \(setCompletions)")

        let setNotes = Array(repeating: "", count: sets)
        let setActualReps = Array(repeating: 0, count: sets)
        
        let newExercise = Exercise(
            recordID: nil,
            name: name,
            sets: sets,
            reps: reps,
            setWeights: setWeights,
            setCompletions: setCompletions,
            setNotes: Array(repeating: "", count: sets),
            exerciseNote: exerciseNote,
            setActualReps: Array(repeating: 0, count: sets),
            timestamp: Date()
        )
        
        // 2) Insert locally
        exercises.insert(newExercise, at: 0)
        
        // 3) Save to CloudKit
        print("ExerciseViewModel: Saving new exercise to CloudKit...")
        self.saveUserExercise(
            name: name,
            sets: sets,
            reps: reps,
            setWeights: setWeights,
            setCompletions: setCompletions,
            setNotes: setNotes,            // <— Provide them
            setActualReps: setActualReps,  // <— Provide them
            workoutID: workoutID
        ) { result in
            switch result {
            case .success(let record):
                print("ExerciseViewModel: Successfully saved to CloudKit. Record ID:", record.recordID)
                
                // 4) Update local recordID so we can do updates/deletions later
                DispatchQueue.main.async {
                    if let index = self.exercises.firstIndex(where: { $0.id == newExercise.id }) {
                        self.exercises[index].recordID = record.recordID
                    }
                }
                
            case .failure(let error):
                print("ExerciseViewModel: Error saving to CloudKit:", error.localizedDescription)
            }
        }
    }
    
    // MARK: - Save to CloudKit
    func saveUserExercise(
        name: String,
        sets: Int,
        reps: Int,
        setWeights: [Double],
        setCompletions: [Bool],
        setNotes: [String],
        setActualReps: [Int],
        workoutID: CKRecord.ID,
        completion: @escaping (Result<CKRecord, Error>) -> Void
    ) {
        print("CloudKitManager: Attempting to save new exercise:")
        print("  Name: \(name)")
        print("  Sets: \(sets)")
        print("  Reps: \(reps)")
        print("  setWeights: \(setWeights)")
        print("  setCompletions: \(setCompletions)")
        print("  Under workoutID: \(workoutID)")

        let record = CKRecord(recordType: "UserExercises")
        record["name"] = name as CKRecordValue
        record["sets"] = sets as CKRecordValue
        record["reps"] = reps as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue
        record["setWeights"] = setWeights as CKRecordValue
        record["setCompletions"] = setCompletions.map { NSNumber(value: $0) } as CKRecordValue
        record["setNotes"] = setNotes as CKRecordValue
        record["setActualReps"] = setActualReps.map { NSNumber(value: $0) } as CKRecordValue
        
        let workoutRef = CKRecord.Reference(recordID: workoutID, action: .none)
        record["workoutRef"] = workoutRef

        privateDatabase.save(record) { savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("CloudKitManager: Error saving exercise:", error.localizedDescription)
                    completion(.failure(error))
                } else if let savedRecord = savedRecord {
                    print("CloudKitManager: Successfully saved exercise with recordID:", savedRecord.recordID)
                    completion(.success(savedRecord))
                }
            }
        }
    }
    
    // MARK: - Fetch Exercises
    func fetchExercises() {
        print("ExerciseViewModel: Fetching exercises from CloudKit for workout:", workoutID)
        
        CloudKitManager.shared.fetchUserExercises(for: workoutID) { result in
            switch result {
            case .failure(let error):
                print("Error fetching from CloudKit:", error.localizedDescription)
                
            case .success(let records):
                print("ExerciseViewModel: Successfully fetched \(records.count) record(s).")
                
                var fetchedExercises: [Exercise] = []
                
                for record in records {
                    if let name = record["name"] as? String,
                       let sets = record["sets"] as? Int,
                       let reps = record["reps"] as? Int {
                        
                        // 1) Parse setWeights, completions, notes
                        let weights = record["setWeights"] as? [Double] ?? Array(repeating: 0.0, count: sets)
                        let completionsArray = record["setCompletions"] as? [NSNumber] ?? []
                        let boolCompletions = completionsArray.map { $0.boolValue }
                        let notes = record["setNotes"] as? [String] ?? Array(repeating: "", count: sets)
                        let timestamp = record["timestamp"] as? Date ?? Date()
                        let exerciseNote = record["exerciseNote"] as? String ?? ""
                        // 2) Parse actualReps, then pad/slice to ensure it has `sets` elements
                        let actualRepsArray = record["setActualReps"] as? [NSNumber] ?? []
                        var actualReps = actualRepsArray.map { $0.intValue }
                        
                        // If not enough elements, pad with zeros
                        if actualReps.count < sets {
                            let needed = sets - actualReps.count
                            actualReps.append(contentsOf: Array(repeating: 0, count: needed))
                        }
                        
                        // If too many elements, slice
                        if actualReps.count > sets {
                            actualReps = Array(actualReps.prefix(sets))
                        }
                        
                        // 3) Create the Exercise
                        let exercise = Exercise(
                            recordID: record.recordID,
                            name: name,
                            sets: sets,
                            reps: reps,
                            setWeights: weights,
                            setCompletions: boolCompletions,
                            setNotes: notes,
                            exerciseNote: exerciseNote,
                            setActualReps: actualReps,
                            timestamp: timestamp
                        )
                        
                        fetchedExercises.append(exercise)
                    } else {
                        print("Skipping record: missing 'name', 'sets', or 'reps'")
                    }
                }
                
                // 4) Assign on the main thread so the UI updates
                DispatchQueue.main.async {
                    self.exercises = fetchedExercises
                }
            }
        }
    }
    
 func updateExercise(
        recordID: CKRecord.ID,
        newName: String? = nil,
        newSets: Int? = nil,
        newNote: String? = nil,
        newWeights: [Double]? = nil, 
        newCompletions: [Bool]? = nil,
        newSetNotes: [String]? = nil,
        newActualReps: [Int]? = nil
    ) {
        print("ExerciseViewModel: Updating record \(recordID) with multiple fields if provided.")
        
        privateDatabase.fetch(withRecordID: recordID) { record, error in
            if let error = error {
                print("Error fetching record for update:", error.localizedDescription)
                return
            }
            guard let record = record else {
                print("No record found for ID:", recordID)
                return
            }
            
            // Only update fields if the caller provided them (not nil).
            if let newName = newName {
                record["name"] = newName as CKRecordValue
            }
            if let newSets = newSets {
                record["sets"] = newSets as CKRecordValue
            }
            if let newNote = newNote {
                record["exerciseNote"] = newNote as CKRecordValue
            }
            if let newWeights = newWeights {
                record["setWeights"] = newWeights as CKRecordValue
            }
            if let newCompletions = newCompletions {
                record["setCompletions"] = newCompletions.map { NSNumber(value: $0) } as CKRecordValue
            }
            if let newSetNotes = newSetNotes {
                record["setNotes"] = newSetNotes as CKRecordValue
            }
            if let newActualReps = newActualReps {
                record["setActualReps"] = newActualReps.map { NSNumber(value: $0) } as CKRecordValue
            }
            
            // Save once, with all changes
            self.privateDatabase.save(record) { savedRecord, error in
                if let error = error {
                    print("Error saving updated record:", error.localizedDescription) // perhaps this is where the error resides
                } else if let savedRecord = savedRecord {
                    print("Successfully updated record in CloudKit:", savedRecord.recordID)
                    
                    // Update local array so SwiftUI sees the changes
                    DispatchQueue.main.async {
                        if let index = self.exercises.firstIndex(where: { $0.recordID == recordID }) {
                            
                            // Update only the fields we changed
                            if let newName = newName {
                                self.exercises[index].name = newName
                            }
                            if let newSets = newSets {
                                self.exercises[index].sets = newSets
                                
                                // 1) Resize arrays to match new set count
                                self.resizeArraysForSets(index: index, newSets: newSets)
                            }
                            if let newNote = newNote {
                                self.exercises[index].exerciseNote = newNote
                            }
                            if let newWeights = newWeights {
                                self.exercises[index].setWeights = newWeights
                            }
                            if let newCompletions = newCompletions {
                                self.exercises[index].setCompletions = newCompletions
                            }
                            if let newSetNotes = newSetNotes {
                                self.exercises[index].setNotes = newSetNotes
                            }
                            if let newActualReps = newActualReps {
                                self.exercises[index].setActualReps = newActualReps
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Resize Arrays to Match 'sets'
    private func resizeArraysForSets(index: Int, newSets: Int) {
        guard index < exercises.count else { return }
        
        var exercise = exercises[index]
        
        // Resize setWeights
        if exercise.setWeights.count < newSets {
            let additional = newSets - exercise.setWeights.count
            exercise.setWeights.append(contentsOf: Array(repeating: 0.0, count: additional))
        } else if exercise.setWeights.count > newSets {
            exercise.setWeights = Array(exercise.setWeights.prefix(newSets))
        }
        
        // Resize setActualReps
        if exercise.setActualReps.count < newSets {
            let additional = newSets - exercise.setActualReps.count
            exercise.setActualReps.append(contentsOf: Array(repeating: 0, count: additional))
        } else if exercise.setActualReps.count > newSets {
            exercise.setActualReps = Array(exercise.setActualReps.prefix(newSets))
        }
        
        // Resize setCompletions
        if exercise.setCompletions.count < newSets {
            let additional = newSets - exercise.setCompletions.count
            exercise.setCompletions.append(contentsOf: Array(repeating: false, count: additional))
        } else if exercise.setCompletions.count > newSets {
            exercise.setCompletions = Array(exercise.setCompletions.prefix(newSets))
        }
        
        // Resize setNotes
        if exercise.setNotes.count < newSets {
            let additional = newSets - exercise.setNotes.count
            exercise.setNotes.append(contentsOf: Array(repeating: "", count: additional))
        } else if exercise.setNotes.count > newSets {
            exercise.setNotes = Array(exercise.setNotes.prefix(newSets))
        }
        
        // Update the exercise in your local array (to trigger SwiftUI updates)
        exercises[index] = exercise
    }

    
    
//    // MARK: - Update Exercise
    func updateExerciseWeights(
        recordID: CKRecord.ID,
        newWeights: [Double],
        newCompletions: [Bool],
        newNotes: [String]
    ) {
        print("ExerciseViewModel: Attempting to update record \(recordID) in CloudKit with new weights:", newWeights)
        
        privateDatabase.fetch(withRecordID: recordID) { record, error in
            if let error = error {
                print("Error fetching record for update:", error.localizedDescription)
                return
            }
            guard let record = record else {
                print("No record found for ID:", recordID)
                return
            }
            
            // Update fields
            record["setWeights"] = newWeights as CKRecordValue
            record["setCompletions"] = newCompletions.map { NSNumber(value: $0) } as CKRecordValue
            record["setNotes"] = newNotes as CKRecordValue
            
            self.privateDatabase.save(record) { savedRecord, error in
                if let error = error {
                    print("Error saving updated record:", error.localizedDescription) // this is the error that gets called
                } else if let savedRecord = savedRecord {
                    print("Successfully updated record in CloudKit:", savedRecord.recordID)
                }
            }
        }
    }
    
    func updateExerciseNotes(
        recordID: CKRecord.ID,
        newNotes: [String],
        exerciseNote: String
    ) {
        print("ExerciseViewModel: Attempting to update record \(recordID) in CloudKit with new notes:", newNotes, "and exerciseNote:", exerciseNote)
        
        privateDatabase.fetch(withRecordID: recordID) { record, error in
            if let error = error {
                print("Error fetching record for update:", error.localizedDescription)
                return
            }
            guard let record = record else {
                print("No record found for ID:", recordID)
                return
            }
            
            // Overwrite setNotes
            record["setNotes"] = newNotes as CKRecordValue
            
            // Overwrite exerciseNote
            record["exerciseNote"] = exerciseNote as CKRecordValue
            
            self.privateDatabase.save(record) { savedRecord, error in
                if let error = error {
                    print("Error saving updated record:", error.localizedDescription)
                } else if let savedRecord = savedRecord {
                    print("Successfully updated record in CloudKit:", savedRecord.recordID)
                    
                    // Update local array so SwiftUI sees the new note
                    DispatchQueue.main.async {
                        if let index = self.exercises.firstIndex(where: { $0.recordID == recordID }) {
                            // Overwrite the old note with the new one
                            self.exercises[index].exerciseNote = exerciseNote
                        }
                    }
                }
            }
        }
    }
    
    func updateExerciseActualReps(
        recordID: CKRecord.ID,
        newActualReps: [Int]
    ) {
        print("ExerciseViewModel: Attempting to update record \(recordID) with new actual reps:", newActualReps)
        
        privateDatabase.fetch(withRecordID: recordID) { record, error in
            if let error = error {
                print("Error fetching record for update:", error.localizedDescription)
                return
            }
            guard let record = record else {
                print("No record found for ID:", recordID)
                return
            }
            
            // Overwrite setActualReps
            record["setActualReps"] = newActualReps.map { NSNumber(value: $0) } as CKRecordValue
            
            self.privateDatabase.save(record) { savedRecord, error in
                if let error = error {
                    print("Error saving updated record:", error.localizedDescription)
                } else if let savedRecord = savedRecord {
                    print("Successfully updated record in CloudKit:", savedRecord.recordID)
                }
            }
        }
    }
    

        func updateExerciseSets(recordID: CKRecord.ID, newSets: Int) {
            print("ExerciseViewModel: Updating 'sets' to \(newSets) in record \(recordID).")
            
            privateDatabase.fetch(withRecordID: recordID) { record, error in
                if let error = error {
                    print("Error fetching record for update:", error.localizedDescription)
                    return
                }
                guard let record = record else {
                    print("No record found for ID:", recordID)
                    return
                }
                
                // Update the CloudKit field
                record["sets"] = newSets as CKRecordValue
                
                // Save the changes
                self.privateDatabase.save(record) { savedRecord, error in
                    if let error = error {
                        print("Error saving updated record:", error.localizedDescription)
                    } else if let savedRecord = savedRecord {
                        print("Successfully updated 'sets' in CloudKit:", savedRecord.recordID)
                        
                        // Update the local array so SwiftUI sees the new sets count
                        DispatchQueue.main.async {
                            if let index = self.exercises.firstIndex(where: { $0.recordID == recordID }) {
                                self.exercises[index].sets = newSets
                            }
                        }
                    }
                }
            }
        }
    
func updateExerciseName(recordID: CKRecord.ID, newName: String) {
    print("ExerciseViewModel: Attempting to update record \(recordID) in CloudKit with new name:", newName)
    
    privateDatabase.fetch(withRecordID: recordID) { record, error in
        if let error = error {
            print("Error fetching record for update:", error.localizedDescription)
            return
        }
        guard let record = record else {
            print("No record found for ID:", recordID)
            return
        }
        
        // Overwrite the 'name' field in CloudKit
        record["name"] = newName as CKRecordValue
        
        // Save changes
        self.privateDatabase.save(record) { savedRecord, error in
            if let error = error {
                print("Error saving updated record:", error.localizedDescription)
            } else if let savedRecord = savedRecord {
                print("Successfully updated record in CloudKit:", savedRecord.recordID)
                
                // Update the local array so SwiftUI sees the new name
                DispatchQueue.main.async {
                    if let index = self.exercises.firstIndex(where: { $0.recordID == recordID }) {
                        self.exercises[index].name = newName
                    }
                }
            }
        }
    }
}
    
    func updateExerciseNote(recordID: CKRecord.ID, newNote: String) {
        print("ExerciseViewModel: Updating 'exerciseNote' to \(newNote) in record \(recordID).")
        
        privateDatabase.fetch(withRecordID: recordID) { record, error in
            if let error = error {
                print("Error fetching record for update:", error.localizedDescription)
                return
            }
            guard let record = record else {
                print("No record found for ID:", recordID)
                return
            }
            
            // Overwrite just the exerciseNote field
            record["exerciseNote"] = newNote as CKRecordValue
            
            self.privateDatabase.save(record) { savedRecord, error in
                if let error = error {
                    print("Error saving updated record:", error.localizedDescription)
                } else if let savedRecord = savedRecord {
                    print("Successfully updated 'exerciseNote' in CloudKit:", savedRecord.recordID)
                    
                    // Update the local array
                    DispatchQueue.main.async {
                        if let index = self.exercises.firstIndex(where: { $0.recordID == recordID }) {
                            self.exercises[index].exerciseNote = newNote
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Delete Exercise
    func deleteExercise(at offsets: IndexSet) {
        offsets.forEach { index in
            let exercise = exercises[index]
            exercises.remove(at: index)  // Remove locally first
            
            // If the exercise has a recordID, we can delete it in CloudKit too
            if let recordID = exercise.recordID {
                privateDatabase.delete(withRecordID: recordID) { _, error in
                    if let error = error {
                        print("Error deleting exercise from CloudKit:", error.localizedDescription)
                    } else {
                        print("Successfully deleted exercise from CloudKit with recordID:", recordID)
                    }
                }
            }
        }
    }
    
    
    // MARK: - Delete All Exercises (Dev Only)
    func deleteAllExercises() {
        let query = CKQuery(recordType: "UserExercises", predicate: NSPredicate(value: true))
        
        privateDatabase.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                print("Error fetching exercises to delete:", error)
                return
            }
            guard let records = records else { return }
            
            let recordIDs = records.map { $0.recordID }
            
            let deleteOp = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            deleteOp.modifyRecordsResultBlock = { result in
                switch result {
                case .failure(let error):
                    print("Error deleting records:", error.localizedDescription)
                case .success:
                    print("Successfully deleted all exercises.")
                }
            }
            self.privateDatabase.add(deleteOp)
        }
    }
}
