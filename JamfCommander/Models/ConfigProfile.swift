//
//  ConfigProfile.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//


import Foundation

// Represents a Configuration Profile summary
struct ConfigProfile: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    
    // Jamf Classic API often returns IDs as numbers or strings, we handle both via a custom init if needed,
    // but standard Codable usually works if the API is consistent.
}

// Represents a Category in Jamf
struct Category: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}

// Wrapper for the API response list
struct ProfileListResponse: Codable {
    let os_x_configuration_profiles: [ConfigProfile]
}